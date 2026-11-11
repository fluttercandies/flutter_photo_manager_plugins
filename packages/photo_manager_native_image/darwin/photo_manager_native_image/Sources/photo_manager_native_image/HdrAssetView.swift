import Flutter
import Photos
import UIKit

/// Creates `HdrAssetView`s; assets are looked up through the plugin's loader cache.
final class HdrAssetViewFactory: NSObject, FlutterPlatformViewFactory {
    private let loader: NativeImageLoader

    init(loader: NativeImageLoader) {
        self.loader = loader
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let params = args as? [String: Any]
        return HdrAssetView(
            frame: frame,
            loader: loader,
            assetId: params?["assetId"] as? String,
            size: (params?["size"] as? NSNumber)?.intValue ?? 0
        )
    }
}

/// A `UIImageView` that shows the image only when it decodes as high dynamic range (iOS 17+).
final class HdrAssetView: NSObject, FlutterPlatformView {
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "photo_manager_native_image.hdr"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    /// Decoded HDR images by asset id, so a page that comes back draws at once instead of
    /// decoding the original again. Assets that decoded as SDR are remembered too and skipped.
    private static let decoded: NSCache<NSString, HdrDecodeResult> = {
        let cache = NSCache<NSString, HdrDecodeResult>()
        cache.countLimit = 3
        return cache
    }()
    private static let sdrAssets: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 200
        return cache
    }()
    private static var liveViews = 0
    private static var clearWork: DispatchWorkItem?
    /// How long decoded images outlive the last view, so closing the viewer frees them.
    static let idleClearDelay: TimeInterval = 10
    static let fadeInDuration: TimeInterval = 0.2

    private let imageView = UIImageView()
    private var requestId: PHImageRequestID = PHInvalidImageRequestID

    init(frame: CGRect, loader: NativeImageLoader, assetId: String?, size: Int) {
        super.init()
        imageView.frame = frame
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = nil
        Self.retainLive()
        guard #available(iOS 17.0, *), let assetId = assetId, size > 0 else { return }
        imageView.preferredImageDynamicRange = .high
        if Self.sdrAssets.object(forKey: assetId as NSString) != nil { return }
        if let hit = Self.decoded.object(forKey: assetId as NSString), hit.shortSide >= size {
            imageView.image = hit.image
            return
        }
        guard let asset = loader.fetchAsset(assetId) else { return }
        load(asset: asset, size: size)
    }

    deinit {
        if requestId != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestId)
        }
        DispatchQueue.main.async { HdrAssetView.releaseLive() }
    }

    func view() -> UIView { imageView }

    /// A first decode fades in so the brighter HDR image does not snap over the base picture.
    private func fadeIn(_ image: UIImage) {
        imageView.alpha = 0
        imageView.image = image
        UIView.animate(withDuration: Self.fadeInDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.imageView.alpha = 1
        }
    }

    private static func retainLive() {
        clearWork?.cancel()
        clearWork = nil
        liveViews += 1
    }

    private static func releaseLive() {
        liveViews = max(0, liveViews - 1)
        guard liveViews == 0 else { return }
        let work = DispatchWorkItem { decoded.removeAllObjects() }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleClearDelay, execute: work)
    }

    /// Pixel size whose shorter side is `shortSide`, never larger than the original.
    static func targetPixelSize(width: CGFloat, height: CGFloat, shortSide: CGFloat) -> CGSize {
        let shorter = min(width, height)
        let longer = max(width, height)
        guard shorter > 0, shortSide < shorter else { return CGSize(width: width, height: height) }
        let long = (shortSide * longer / shorter).rounded()
        return width >= height ? CGSize(width: long, height: shortSide) : CGSize(width: shortSide, height: long)
    }

    @available(iOS 17.0, *)
    private func load(asset: PHAsset, size: Int) {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        let pixelSize = Self.targetPixelSize(
            width: CGFloat(asset.pixelWidth), height: CGFloat(asset.pixelHeight), shortSide: CGFloat(size))
        requestId = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) {
            [weak self] data, _, _, _ in
            guard let data = data, self != nil else { return }
            HdrAssetView.queue.addOperation { [weak self] in
                guard self != nil else { return }
                var configuration = UIImageReader.Configuration()
                configuration.prefersHighDynamicRange = true
                configuration.preparesImagesForDisplay = true
                configuration.preferredThumbnailSize = pixelSize
                let key = asset.localIdentifier as NSString
                guard let image = UIImageReader(configuration: configuration).image(data: data),
                      image.isHighDynamicRange else {
                    HdrAssetView.sdrAssets.setObject(NSNumber(value: true), forKey: key)
                    return
                }
                // The request size is what a later view asks for; an original smaller than it is already full size.
                HdrAssetView.decoded.setObject(HdrDecodeResult(image: image, shortSide: size), forKey: key)
                DispatchQueue.main.async { [weak self] in
                    self?.fadeIn(image)
                }
            }
        }
    }
}

/// A decoded HDR image and the shorter side it was requested at.
final class HdrDecodeResult {
    let image: UIImage
    let shortSide: Int

    init(image: UIImage, shortSide: Int) {
        self.image = image
        self.shortSide = shortSide
    }
}
