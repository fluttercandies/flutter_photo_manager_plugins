import AVFoundation
import Flutter
import Photos

/// Owns one AVPlayer built from the `AVPlayerItem` PhotoKit hands back, and
/// publishes its frames as a Flutter texture.
///
/// The sandbox extension that grants access rides on that player item —
/// extracting a URL from it and playing it elsewhere fails with
/// NSCocoaErrorDomain 257 on iOS 18+, which is why this player and PhotoKit
/// have to live together.
class GalleryVideoPlayer: NSObject {
    private(set) var textureId: Int64 = 0

    private let registry: FlutterTextureRegistry
    private let localIdentifier: String
    private let allowNetworkAccess: Bool
    private let initialVolume: Double

    /// Kept so `release()` can clear it; the registration holds `self` strongly.
    private var events: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private var avPlayer: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?

    /// Read on the raster thread, written on the main thread.
    private var latestPixelBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()

    private var preparing = false
    private var released = false
    private var initializedEventSent = false
    private var firstFrameEmitted = false
    private var isLooping: Bool

    /// PhotoKit resolves asynchronously, so a caller can ask to play or set the
    /// volume before there is a player to act on.
    private var pendingAutoplay = false
    private var pendingVolume: Double?

    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var bufferingObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var imageRequestId: PHImageRequestID?

    init(
        registry: FlutterTextureRegistry,
        messenger: FlutterBinaryMessenger,
        localIdentifier: String,
        allowNetworkAccess: Bool,
        looping: Bool,
        volume: Double
    ) {
        self.registry = registry
        self.localIdentifier = localIdentifier
        self.allowNetworkAccess = allowNetworkAccess
        self.isLooping = looping
        self.initialVolume = volume
        super.init()

        textureId = registry.register(self)
        let channel = FlutterEventChannel(
            name: "\(PhotoManagerVideoPlayerPlugin.channelName)/events/\(textureId)",
            binaryMessenger: messenger
        )
        channel.setStreamHandler(self)
        events = channel
    }

    /// Resolves the `PHAsset` and asks PhotoKit for its `AVPlayerItem`. Idempotent.
    func prepare() {
        if preparing || released { return }
        preparing = true

        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            // Without library access PhotoKit finds nothing, which is not the asset's fault.
            if libraryAccessDenied() {
                emitError(code: "permissionDenied", message: "Photo library access is not granted.")
            } else {
                emitError(code: "assetNotFound", message: "Asset \(localIdentifier) is not available.")
            }
            return
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = allowNetworkAccess
        options.deliveryMode = .automatic
        options.progressHandler = { [weak self] progress, _, _, _ in
            DispatchQueue.main.async {
                self?.emit(event: "downloadProgress", extra: ["progress": progress])
            }
        }

        imageRequestId = PHImageManager.default().requestPlayerItem(
            forVideo: asset, options: options
        ) { [weak self] playerItem, info in
            DispatchQueue.main.async {
                self?.handlePlayerItemResult(playerItem, info: info)
            }
        }
    }

    private func handlePlayerItemResult(_ playerItem: AVPlayerItem?, info: [AnyHashable: Any]?) {
        if released { return }
        if (info?[PHImageCancelledKey] as? Bool) == true { return }

        guard let playerItem else {
            emitError(code: mapErrorCode(info), message: mapErrorMessage(info))
            return
        }

        // The colour properties tone-map HDR footage to SDR for the texture.
        let output = AVPlayerItemVideoOutput(outputSettings: [
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ])
        playerItem.add(output)
        videoOutput = output

        if let track = playerItem.asset.tracks(withMediaType: .video).first {
            let upright = track.naturalSize.applying(track.preferredTransform)
            emit(event: "videoSize", extra: [
                "width": abs(upright.width),
                "height": abs(upright.height),
                "rotationDegrees": rotationDegrees(of: track.preferredTransform),
            ])
        }

        let player = AVPlayer(playerItem: playerItem)
        // Keeping the rate at the end lets a loop rewind without a pause in between.
        player.actionAtItemEnd = isLooping ? .none : .pause
        player.volume = Float(pendingVolume ?? initialVolume).clamped(to: 0...1)
        pendingVolume = nil
        avPlayer = player

        let link = CADisplayLink(target: self, selector: #selector(onDisplayLink))
        link.add(to: .main, forMode: .common)
        displayLink = link

        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async { self?.handleStatusChange(item) }
        }
        bufferingObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.emit(event: "buffering", extra: ["isBuffering": !item.isPlaybackLikelyToKeepUp])
            }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let isPlaying = player.rate != 0
                // Frames only need pushing while the picture moves.
                self.displayLink?.isPaused = !isPlaying && self.firstFrameEmitted
                self.emit(event: "playing", extra: ["isPlaying": isPlaying])
            }
        }

        if pendingAutoplay {
            pendingAutoplay = false
            player.play()
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, player.rate != 0, let ms = time.safeMilliseconds else { return }
            self.emit(event: "position", extra: ["positionMs": ms])
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackEnded()
        }
    }

    /// Quarter-turn the track is stored rotated by. The texture receives raw
    /// decoder output, which ignores orientation, so Dart applies this.
    private func rotationDegrees(of transform: CGAffineTransform) -> Int {
        let radians = atan2(transform.b, transform.a)
        let degrees = Int((radians * 180 / .pi).rounded())
        return ((degrees % 360) + 360) % 360
    }

    @objc private func onDisplayLink() {
        guard let output = videoOutput else { return }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }

        bufferLock.lock()
        latestPixelBuffer = buffer
        bufferLock.unlock()
        registry.textureFrameAvailable(textureId)

        if !firstFrameEmitted {
            firstFrameEmitted = true
            emit(event: "firstFrame")
        }
        // While playback is stopped the link runs only to land one frame.
        if avPlayer?.rate == 0 {
            displayLink?.isPaused = true
        }
    }

    private func handleStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            guard !initializedEventSent, let durationMs = item.duration.safeMilliseconds else { return }
            initializedEventSent = true
            emit(event: "initialized", extra: ["durationMs": durationMs])
        case .failed:
            // No frame will ever arrive, so the link would otherwise fire every vsync.
            displayLink?.invalidate()
            displayLink = nil
            emitError(
                code: "playbackFailed",
                message: item.error?.localizedDescription ?? "Playback failed.")
        default:
            break
        }
    }

    private func handlePlaybackEnded() {
        if isLooping {
            avPlayer?.seek(to: .zero)
        } else {
            emit(event: "completed")
        }
    }

    func play() {
        guard let avPlayer else {
            pendingAutoplay = true
            return
        }
        if let item = avPlayer.currentItem, CMTIME_IS_NUMERIC(item.duration),
           item.currentTime() >= CMTimeSubtract(item.duration, endTolerance) {
            restart()
            return
        }
        avPlayer.play()
    }

    /// Replays from the start. The rewind has to land before playback resumes,
    /// or the player just runs off the end it is already sitting on.
    private func restart() {
        avPlayer?.seek(to: .zero) { [weak self] _ in
            self?.avPlayer?.play()
        }
    }

    func pause() {
        pendingAutoplay = false
        avPlayer?.pause()
    }

    func seek(toMilliseconds ms: Int64) {
        avPlayer?.seek(
            to: CMTime(value: ms, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        // Resume frame pushes so a paused seek still repaints, and report the
        // position the periodic observer would skip while paused.
        displayLink?.isPaused = false
        emit(event: "position", extra: ["positionMs": ms])
    }

    func setVolume(_ volume: Double) {
        guard let avPlayer else {
            pendingVolume = volume
            return
        }
        avPlayer.volume = Float(volume).clamped(to: 0...1)
    }

    func setLooping(_ looping: Bool) {
        isLooping = looping
        avPlayer?.actionAtItemEnd = looping ? .none : .pause
    }

    func release() {
        if released { return }
        released = true
        if let imageRequestId {
            PHImageManager.default().cancelImageRequest(imageRequestId)
        }
        if let timeObserver {
            avPlayer?.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        statusObservation?.invalidate()
        rateObservation?.invalidate()
        bufferingObservation?.invalidate()
        displayLink?.invalidate()
        displayLink = nil
        avPlayer?.pause()
        avPlayer = nil
        videoOutput = nil
        bufferLock.lock()
        latestPixelBuffer = nil
        bufferLock.unlock()
        registry.unregisterTexture(textureId)
        eventSink = nil
        events?.setStreamHandler(nil)
        events = nil
    }

    private func emit(event: String, extra: [String: Any] = [:]) {
        var payload: [String: Any] = ["event": event]
        payload.merge(extra) { _, new in new }
        eventSink?(payload)
    }

    private func emitError(code: String, message: String) {
        emit(event: "error", extra: ["code": code, "message": message])
    }
}

extension GalleryVideoPlayer: FlutterTexture {
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard let buffer = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}

extension GalleryVideoPlayer: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink)
        -> FlutterError? {
        self.eventSink = eventSink
        prepare()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

/// Whether the app has no photo library access at all (limited access counts as access).
private func libraryAccessDenied() -> Bool {
    let status: PHAuthorizationStatus
    if #available(iOS 14, *) {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    } else {
        status = PHPhotoLibrary.authorizationStatus()
    }
    return status == .denied || status == .restricted || status == .notDetermined
}

/// (code, message) for a failed `requestPlayerItem`, matching
/// `AssetEntityVideoErrorCode` on the Dart side.
private func mapErrorCode(_ info: [AnyHashable: Any]?) -> String {
    if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
        return "iCloudUnavailable"
    }
    if let error = info?[PHImageErrorKey] as? NSError,
       error.domain == NSCocoaErrorDomain, error.code == 257 {
        return "permissionDenied"
    }
    return "playbackFailed"
}

private func mapErrorMessage(_ info: [AnyHashable: Any]?) -> String {
    if let error = info?[PHImageErrorKey] as? NSError {
        return error.localizedDescription
    }
    if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
        return "This asset is only in iCloud and network access is disabled."
    }
    return "PhotoKit could not produce a player item for this asset."
}

/// How close to the item's duration still counts as "at the end".
private let endTolerance = CMTime(value: 100, timescale: 1000)

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension CMTime {
    /// Milliseconds, or nil for a time Swift's `Int(_:)` would trap on
    /// (`.indefinite` is NaN; a huge value overflows).
    var safeMilliseconds: Int? {
        guard CMTIME_IS_NUMERIC(self) else { return nil }
        let ms = seconds * 1000
        guard ms.isFinite, ms > Double(Int.min), ms < Double(Int.max) else { return nil }
        return Int(ms)
    }
}
