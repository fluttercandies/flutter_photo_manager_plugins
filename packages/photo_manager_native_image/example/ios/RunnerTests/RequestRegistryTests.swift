import XCTest
@testable import photo_manager_native_image

final class RequestRegistryTests: XCTestCase {
    private func state(_ id: Int64, _ sink: @escaping (Result<NativeImageReply?, Error>) -> Void = { _ in }) -> NativeImageRequestState {
        NativeImageRequestState(requestId: id, completion: sink)
    }

    func testFinishDeliversExactlyOnce() {
        var replies = 0
        let s = state(1) { _ in replies += 1 }
        XCTAssertTrue(s.finish(.success(nil)))
        XCTAssertFalse(s.finish(.success(["pointer": 1])))
        XCTAssertFalse(s.finish(.failure(NativeImageError(code: "decode_failed", message: nil, details: nil))))
        XCTAssertEqual(replies, 1)
        XCTAssertTrue(s.isDone)
    }

    func testCancelBeforeAllocationMarksState() {
        let registry = NativeImageRequestRegistry()
        let s = state(7)
        XCTAssertTrue(registry.register(s))
        registry.cancel(requestId: 7)
        XCTAssertTrue(s.isCancelled)
        XCTAssertEqual(registry.cancelledAheadCount, 0)
    }

    func testCancelAheadOfRequestIsConsumedOnce() {
        let registry = NativeImageRequestRegistry()
        registry.cancel(requestId: 3)
        XCTAssertEqual(registry.cancelledAheadCount, 1)
        XCTAssertFalse(registry.register(state(3)))
        XCTAssertEqual(registry.cancelledAheadCount, 0)
        XCTAssertTrue(registry.register(state(3)))
    }

    func testCancelAfterRemovalDoesNotResurrectRequest() {
        let registry = NativeImageRequestRegistry()
        let s = state(9)
        XCTAssertTrue(registry.register(s))
        registry.remove(requestId: 9)
        registry.cancel(requestId: 9)
        XCTAssertFalse(s.isCancelled)
        XCTAssertEqual(registry.pendingCount, 0)
    }

    func testCancelledAheadSetIsBounded() {
        let registry = NativeImageRequestRegistry()
        for id in 0..<Int64(NativeImageRequestRegistry.cancelledAheadLimit + 5) {
            registry.cancel(requestId: id)
        }
        XCTAssertLessThanOrEqual(registry.cancelledAheadCount, NativeImageRequestRegistry.cancelledAheadLimit)
    }

    func testCancelAllDrainsPending() {
        let registry = NativeImageRequestRegistry()
        let a = state(1), b = state(2)
        _ = registry.register(a)
        _ = registry.register(b)
        let drained = registry.cancelAll()
        XCTAssertEqual(drained.count, 2)
        XCTAssertTrue(a.isCancelled && b.isCancelled)
        XCTAssertEqual(registry.pendingCount, 0)
    }

    func testBufferProducedAfterDetachIsFreed() {
        let registry = NativeImageRequestRegistry()
        var replies: [NativeImageReply?] = []
        let s = state(11) { if case .success(let r) = $0 { replies.append(r) } }
        XCTAssertTrue(registry.register(s))
        // Engine detach settles the request before the worker hands back its buffer.
        registry.cancelAll().forEach { $0.finish(.success(nil)) }
        let pointer = malloc(4)!
        var freed: [UnsafeMutableRawPointer] = []
        let reply: NativeImageReply = ["pointer": Int64(Int(bitPattern: pointer)), "width": 1, "height": 1, "rowBytes": 4]
        let accepted = s.deliver(.success(reply)) { freed.append($0) }
        XCTAssertFalse(accepted)
        XCTAssertEqual(freed, [pointer])
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies[0])
        free(pointer)
    }

    func testReplyQueuedBeforeDetachIsFreed() {
        let registry = NativeImageRequestRegistry()
        let attachment = EngineAttachment()
        var replies = 0
        var freed = 0
        let s = NativeImageRequestState(
            requestId: 14,
            completion: attachment.mainThreadReply({ _ in replies += 1 }) {
                freed += 1
                free($0)
            })
        XCTAssertTrue(registry.register(s))
        let delivered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let pointer = malloc(16)!
            registry.remove(requestId: 14)
            s.deliver(.success(["pointer": Int64(Int(bitPattern: pointer)), "width": 2, "height": 2, "rowBytes": 8])) { free($0) }
            delivered.signal()
        }
        // The main queue is held here, so the reply is queued but not yet sent.
        delivered.wait()
        attachment.attached = false
        XCTAssertTrue(registry.cancelAll().isEmpty)
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(replies, 0)
        XCTAssertEqual(freed, 1)
    }

    func testReplyWhileAttachedIsSentAndNotFreed() {
        var replies = 0
        var freed = 0
        replyOrFree(.success(["pointer": 0x1000]), attached: true, reply: { _ in replies += 1 }) { _ in freed += 1 }
        XCTAssertEqual(replies, 1)
        XCTAssertEqual(freed, 0)
    }

    func testAcceptedBufferIsNotFreed() {
        let s = state(12)
        var freed = 0
        XCTAssertTrue(s.deliver(.success(["pointer": 0x1000])) { _ in freed += 1 })
        XCTAssertEqual(freed, 0)
    }

    func testRejectedErrorOrNullFreesNothing() {
        let s = state(13)
        s.finish(.success(nil))
        var freed = 0
        XCTAssertFalse(s.deliver(.failure(NativeImageError(code: "decode_failed", message: nil, details: nil))) { _ in freed += 1 })
        XCTAssertFalse(s.deliver(.success(nil)) { _ in freed += 1 })
        XCTAssertEqual(freed, 0)
    }

    func testCancelRunsTheHookOnce() {
        let registry = NativeImageRequestRegistry()
        let s = state(21)
        XCTAssertTrue(registry.register(s))
        var calls = 0
        XCTAssertTrue(s.setCancelHook { calls += 1 })
        registry.cancel(requestId: 21)
        registry.cancel(requestId: 21)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(s.isCancelled)
    }

    func testHookIsRejectedAfterCancel() {
        let s = state(22)
        s.markCancelled()
        var calls = 0
        XCTAssertFalse(s.setCancelHook { calls += 1 })
        XCTAssertEqual(calls, 0)
    }

    func testRemovedHookIsNotCalled() {
        let s = state(23)
        var calls = 0
        XCTAssertTrue(s.setCancelHook { calls += 1 })
        s.setCancelHook(nil)
        s.markCancelled()
        XCTAssertEqual(calls, 0)
    }

    func testEngineDetachRunsPendingHooks() {
        let registry = NativeImageRequestRegistry()
        let s = state(24)
        XCTAssertTrue(registry.register(s))
        var calls = 0
        s.setCancelHook { calls += 1 }
        _ = registry.cancelAll()
        XCTAssertEqual(calls, 1)
    }

    func testConcurrentFinishDeliversOnce() {
        let counter = NSLock()
        var replies = 0
        let s = state(5) { _ in counter.lock(); replies += 1; counter.unlock() }
        DispatchQueue.concurrentPerform(iterations: 32) { _ in _ = s.finish(.success(nil)) }
        XCTAssertEqual(replies, 1)
    }
}
