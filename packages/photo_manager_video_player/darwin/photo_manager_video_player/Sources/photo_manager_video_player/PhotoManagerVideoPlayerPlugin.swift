import Flutter
import UIKit

public class PhotoManagerVideoPlayerPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.fluttercandies/photo_manager_video_player"
    static let viewType = "\(channelName)/view"

    private let registry: FlutterTextureRegistry
    private let messenger: FlutterBinaryMessenger
    private var players: [Int64: GalleryVideoPlayer] = [:]

    // Texture ids count up from 0, so platform-view players count down from -1.
    private var nextPlatformViewPlayerId: Int64 = -1

    /// Players the engine still owns; read by the engine-teardown test.
    var playerCount: Int { players.count }

    init(registry: FlutterTextureRegistry, messenger: FlutterBinaryMessenger) {
        self.registry = registry
        self.messenger = messenger
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PhotoManagerVideoPlayerPlugin(
            registry: registrar.textures(),
            messenger: registrar.messenger()
        )
        let channel = FlutterMethodChannel(
            name: channelName, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.register(
            PlatformVideoViewFactory { [weak instance] id in instance?.players[id] },
            withId: viewType)
        // Only published instances receive detachFromEngine(for:).
        registrar.publish(instance)
    }

    /// Releases every outstanding player when the engine tears down, so no
    /// `AVPlayer` or registered texture outlives the engine that owned it.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        releaseAll()
    }

    private func releaseAll() {
        players.values.forEach { $0.release() }
        players.removeAll()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        // A hot restart keeps the engine, so players from the previous isolate
        // would keep holding decoders with no Dart side left to dispose them.
        if call.method == "disposeAll" {
            releaseAll()
            return result(nil)
        }

        if call.method == "create" {
            guard let assetId = args["assetId"] as? String else {
                return result(FlutterError(
                    code: "playbackFailed", message: "Missing 'assetId'.", details: nil))
            }
            AudioSession.upgradeForPlaybackOnce()
            let platformViewPlayerId: Int64?
            if args["viewType"] as? String == "platformView" {
                platformViewPlayerId = nextPlatformViewPlayerId
                nextPlatformViewPlayerId -= 1
            } else {
                platformViewPlayerId = nil
            }
            let player = GalleryVideoPlayer(
                registry: registry,
                messenger: messenger,
                platformViewPlayerId: platformViewPlayerId,
                localIdentifier: assetId,
                allowNetworkAccess: args["allowNetworkAccess"] as? Bool ?? true,
                looping: args["looping"] as? Bool ?? false,
                volume: args["volume"] as? Double ?? 1.0
            )
            players[player.playerId] = player
            return result(player.playerId)
        }

        guard let textureId = (args["textureId"] as? NSNumber)?.int64Value,
              let player = players[textureId] else {
            return result(FlutterError(
                code: "playbackFailed", message: "No player for the given texture.", details: nil))
        }

        switch call.method {
        case "play": player.play()
        case "pause": player.pause()
        case "seekTo": player.seek(toMilliseconds: (args["positionMs"] as? NSNumber)?.int64Value ?? 0)
        case "setVolume": player.setVolume(args["volume"] as? Double ?? 1.0)
        case "setLooping": player.setLooping(args["looping"] as? Bool ?? false)
        case "dispose": players.removeValue(forKey: textureId)?.release()
        default: return result(FlutterMethodNotImplemented)
        }
        result(nil)
    }
}
