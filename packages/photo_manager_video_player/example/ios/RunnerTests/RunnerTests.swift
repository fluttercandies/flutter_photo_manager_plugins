import Flutter
import XCTest
@testable import photo_manager_video_player

final class PluginLifecycleTests: XCTestCase {
    private let pluginKey = "PhotoManagerVideoPlayerPlugin"

    private func create(_ plugin: PhotoManagerVideoPlayerPlugin) {
        let done = expectation(description: "create")
        plugin.handle(
            FlutterMethodCall(methodName: "create", arguments: ["assetId": "missing-asset"])
        ) { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    /// The engine only calls detachFromEngine on published plugin instances.
    func testRegisterPublishesTheInstance() {
        let engine = FlutterEngine(name: "publish", project: nil, allowHeadlessExecution: true)
        XCTAssertTrue(engine.run())
        PhotoManagerVideoPlayerPlugin.register(with: engine.registrar(forPlugin: pluginKey)!)
        XCTAssertTrue(engine.valuePublished(byPlugin: pluginKey) is PhotoManagerVideoPlayerPlugin)
        engine.destroyContext()
    }

    func testEngineTeardownReleasesPlayersWithoutDartDispose() throws {
        var plugin: PhotoManagerVideoPlayerPlugin?
        autoreleasepool {
            var engine: FlutterEngine? = FlutterEngine(
                name: "teardown", project: nil, allowHeadlessExecution: true)
            XCTAssertTrue(engine!.run())
            PhotoManagerVideoPlayerPlugin.register(with: engine!.registrar(forPlugin: pluginKey)!)
            plugin = engine!.valuePublished(byPlugin: pluginKey) as? PhotoManagerVideoPlayerPlugin
            guard let plugin = plugin else { return }
            create(plugin)
            create(plugin)
            XCTAssertEqual(plugin.playerCount, 2)
            engine!.destroyContext()
            engine = nil
        }
        let survivor = try XCTUnwrap(plugin, "plugin was never published")
        XCTAssertEqual(survivor.playerCount, 0)
    }
}
