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

    private let imageView = UIImageView()
    private var requestId: PHImageRequestID = PHInvalidImageRequestID

    init(frame: CGRect, loader: NativeImageLoader, assetId: String?, size: Int) {
        super.init()
        imageView.frame = frame
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = nil
        guard #available(iOS 17.0, *), let assetId = assetId, size > 0,
              let asset = loader.fetchAsset(assetId) else { return }
        imageView.preferredImageDynamicRange = .high
        load(asset: asset, size: size)
    }

    deinit {
        if requestId != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestId)
        }
    }

    func view() -> UIView { imageView }

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
                guard let image = UIImageReader(configuration: configuration).image(data: data),
                      image.isHighDynamicRange else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.imageView.image = image
                }
            }
        }
    }
}
