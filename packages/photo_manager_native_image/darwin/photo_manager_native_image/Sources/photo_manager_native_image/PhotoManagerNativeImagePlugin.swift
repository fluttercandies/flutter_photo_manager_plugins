import Flutter
import UIKit

public class PhotoManagerNativeImagePlugin: NSObject, FlutterPlugin {
    private let loader = NativeImageLoader()
    private let attachment = EngineAttachment()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PhotoManagerNativeImagePlugin()
        NativeImageHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        registrar.publish(instance)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        attachment.attached = false
        loader.cancelAll()
    }
}

extension PhotoManagerNativeImagePlugin: NativeImageHostApi {
    func requestImage(
        assetId: String, requestId: Int64, width: Int64, height: Int64,
        isVideo: Bool, allowNetwork: Bool,
        completion: @escaping (Result<[String: Int64]?, Error>) -> Void
    ) {
        loader.request(
            assetId: assetId,
            requestId: requestId,
            targetSize: CGSize(width: CGFloat(width), height: CGFloat(height)),
            allowNetwork: allowNetwork,
            completion: attachment.mainThreadReply(completion)
        )
    }

    func cancelRequest(requestId: Int64) throws {
        loader.cancel(requestId: requestId)
    }
}
