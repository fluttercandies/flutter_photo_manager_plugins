import Foundation

/// Reply payload: `{pointer, width, height, rowBytes}`.
typealias NativeImageReply = [String: Int64]

/// One in-flight request. `finish` delivers the reply exactly once no matter
/// how many exit paths race to call it.
final class NativeImageRequestState {
    let requestId: Int64
    private let lock = NSLock()
    private var done = false
    private var cancelled = false
    private var completion: ((Result<NativeImageReply?, Error>) -> Void)?

    init(requestId: Int64, completion: @escaping (Result<NativeImageReply?, Error>) -> Void) {
        self.requestId = requestId
        self.completion = completion
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    var isDone: Bool {
        lock.lock(); defer { lock.unlock() }
        return done
    }

    private var cancelHook: (() -> Void)?

    /// Installs a hook that stops work already in progress (an iCloud
    /// download). Returns false, without installing it, if the request was
    /// cancelled first; passing nil removes the hook.
    @discardableResult
    func setCancelHook(_ hook: (() -> Void)?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled && hook != nil { return false }
        cancelHook = hook
        return true
    }

    func markCancelled() {
        lock.lock()
        cancelled = true
        let hook = cancelHook
        cancelHook = nil
        lock.unlock()
        hook?()
    }

    /// Delivers a worker's result. A buffer only becomes Dart's once the reply
    /// is accepted; if the request was already settled (engine detach), it is
    /// freed here.
    @discardableResult
    func deliver(_ result: Result<NativeImageReply?, Error>, free: (UnsafeMutableRawPointer) -> Void) -> Bool {
        if finish(result) { return true }
        freeBuffer(in: result, free)
        return false
    }

    /// Returns `true` if this call delivered the reply, `false` if it was
    /// already delivered.
    @discardableResult
    func finish(_ result: Result<NativeImageReply?, Error>) -> Bool {
        lock.lock()
        if done {
            lock.unlock()
            return false
        }
        done = true
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(result)
        return true
    }
}

/// Whether the engine the plugin serves is still attached. Read and written
/// on the main thread only.
final class EngineAttachment {
    var attached = true

    /// Wraps `reply` so it runs on the main thread and checks the engine
    /// there, after any detach queued before it. The engine drops a reply
    /// sent after it detached, so a buffer in such a reply is freed instead.
    func mainThreadReply(
        _ reply: @escaping (Result<NativeImageReply?, Error>) -> Void,
        free: @escaping (UnsafeMutableRawPointer) -> Void = { Foundation.free($0) }
    ) -> (Result<NativeImageReply?, Error>) -> Void {
        return { result in
            DispatchQueue.main.async {
                replyOrFree(result, attached: self.attached, reply: reply, free: free)
            }
        }
    }
}

/// Sends `result` if the engine is still attached; otherwise the reply would
/// be dropped by the engine, so a buffer it carries is freed instead.
func replyOrFree(
    _ result: Result<NativeImageReply?, Error>,
    attached: Bool,
    reply: (Result<NativeImageReply?, Error>) -> Void,
    free: (UnsafeMutableRawPointer) -> Void
) {
    if attached {
        reply(result)
    } else {
        freeBuffer(in: result, free)
    }
}

private func freeBuffer(
    in result: Result<NativeImageReply?, Error>, _ free: (UnsafeMutableRawPointer) -> Void
) {
    if case .success(let reply?) = result, let address = reply["pointer"],
       let pointer = UnsafeMutableRawPointer(bitPattern: Int(address)) {
        free(pointer)
    }
}

/// Tracks requests between arrival and reply so that cancels can be applied
/// before a buffer is allocated. Cancels for ids not yet seen are remembered
/// and consumed by the request when it arrives.
final class NativeImageRequestRegistry {
    static let cancelledAheadLimit = 4096

    private let lock = NSLock()
    private var pending: [Int64: NativeImageRequestState] = [:]
    private var cancelledAhead: Set<Int64> = []

    /// Registers a request. Returns `false` when a cancel for this id arrived
    /// first; the caller must reply `nil` without doing any work.
    func register(_ state: NativeImageRequestState) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelledAhead.remove(state.requestId) != nil {
            return false
        }
        pending[state.requestId] = state
        return true
    }

    func cancel(requestId: Int64) {
        lock.lock()
        let state = pending[requestId]
        if state == nil {
            // A cancel that raced an already-sent reply would otherwise pin
            // its id here forever; the set is a hint, so it is safe to drop.
            if cancelledAhead.count >= Self.cancelledAheadLimit {
                cancelledAhead.removeAll()
            }
            cancelledAhead.insert(requestId)
        }
        lock.unlock()
        // Outside the lock: the cancel hook calls into PhotoKit.
        state?.markCancelled()
    }

    func remove(requestId: Int64) {
        lock.lock(); defer { lock.unlock() }
        pending.removeValue(forKey: requestId)
    }

    /// Cancels and drains every pending request (engine detach).
    func cancelAll() -> [NativeImageRequestState] {
        lock.lock()
        let states = Array(pending.values)
        pending.removeAll()
        cancelledAhead.removeAll()
        lock.unlock()
        states.forEach { $0.markCancelled() }
        return states
    }

    var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pending.count
    }

    var cancelledAheadCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cancelledAhead.count
    }
}
