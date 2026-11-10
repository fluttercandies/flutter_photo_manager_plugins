import AVFoundation
import Flutter
import UIKit

/// An `AVPlayerLayer` embedded as a platform view. Unlike a texture, the layer
/// is composited by the system, so HDR video is shown in EDR on HDR screens and
/// tone-mapped on SDR ones.
class PlatformVideoView: NSObject, FlutterPlatformView {
    private let container = PlayerLayerView()
    private weak var player: GalleryVideoPlayer?
    private var readyObservation: NSKeyValueObservation?

    init(frame: CGRect, player: GalleryVideoPlayer?) {
        self.player = player
        super.init()
        container.frame = frame
        container.isUserInteractionEnabled = false
        container.playerLayer.videoGravity = .resizeAspect
        readyObservation = container.playerLayer.observe(
            \.isReadyForDisplay, options: [.initial, .new]
        ) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.player?.frameRendered() }
        }
        player?.platformView = self
    }

    deinit {
        readyObservation?.invalidate()
    }

    func view() -> UIView { container }

    /// Shows [avPlayer], or nothing once the player is released.
    func show(_ avPlayer: AVPlayer?) {
        container.playerLayer.player = avPlayer
    }
}

private class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Builds a [PlatformVideoView] for the `playerId` in the creation params.
class PlatformVideoViewFactory: NSObject, FlutterPlatformViewFactory {
    private let findPlayer: (Int64) -> GalleryVideoPlayer?

    init(findPlayer: @escaping (Int64) -> GalleryVideoPlayer?) {
        self.findPlayer = findPlayer
        super.init()
    }

    func create(
        withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
    ) -> FlutterPlatformView {
        let playerId = ((args as? [String: Any])?["playerId"] as? NSNumber)?.int64Value
        // A view outliving its player (disposed mid-build) shows nothing.
        return PlatformVideoView(frame: frame, player: playerId.flatMap(findPlayer))
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}
