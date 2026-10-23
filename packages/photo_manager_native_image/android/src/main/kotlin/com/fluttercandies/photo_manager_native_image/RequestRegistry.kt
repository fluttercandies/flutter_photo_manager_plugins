package com.fluttercandies.photo_manager_native_image

/** Reply payload: `{pointer, width, height, rowBytes}`. */
typealias NativeImageReply = Map<String, Long>

/**
 * One in-flight request. [finish] delivers the reply exactly once no matter
 * how many exit paths race to call it.
 */
class RequestState(
    val requestId: Long,
    completion: (Result<NativeImageReply?>) -> Unit,
) {
    private val lock = Any()
    private var done = false
    private var completion: ((Result<NativeImageReply?>) -> Unit)? = completion

    @Volatile
    var isCancelled: Boolean = false
        private set

    val isDone: Boolean
        get() = synchronized(lock) { done }

    fun markCancelled() {
        isCancelled = true
    }

    /**
     * Delivers a worker's result. A buffer only becomes Dart's once the reply is
     * accepted; if the request was already settled (engine detach), it is freed here.
     */
    fun deliver(result: Result<NativeImageReply?>, free: (Long) -> Unit): Boolean {
        if (finish(result)) return true
        result.getOrNull()?.get("pointer")?.let(free)
        return false
    }

    /** Returns `true` if this call delivered the reply. */
    fun finish(result: Result<NativeImageReply?>): Boolean {
        val callback = synchronized(lock) {
            if (done) return false
            done = true
            completion.also { completion = null }
        }
        callback?.invoke(result)
        return true
    }
}

/**
 * Sends [result] if the engine is still attached; otherwise the reply would be
 * dropped by the engine, so a buffer it carries is freed instead.
 */
fun replyOrFree(
    result: Result<NativeImageReply?>,
    attached: Boolean,
    callback: (Result<NativeImageReply?>) -> Unit,
    free: (Long) -> Unit,
) {
    if (attached) {
        callback(result)
    } else {
        result.getOrNull()?.get("pointer")?.let(free)
    }
}

/**
 * Tracks requests between arrival and reply so cancels can be applied before
 * a buffer is allocated. Cancels for ids not yet seen are remembered and
 * consumed by the request when it arrives.
 */
class RequestRegistry {
    private val lock = Any()
    private val pending = HashMap<Long, RequestState>()
    private val cancelledAhead = HashSet<Long>()

    /**
     * Registers a request. Returns `false` when a cancel for this id arrived
     * first; the caller must reply `null` without doing any work.
     */
    fun register(state: RequestState): Boolean = synchronized(lock) {
        if (cancelledAhead.remove(state.requestId)) {
            return false
        }
        pending[state.requestId] = state
        true
    }

    fun cancel(requestId: Long) = synchronized(lock) {
        val state = pending[requestId]
        if (state != null) {
            state.markCancelled()
        } else {
            // A cancel that raced an already-sent reply would otherwise pin
            // its id here forever; the set is a hint, so it is safe to drop.
            if (cancelledAhead.size >= CANCELLED_AHEAD_LIMIT) {
                cancelledAhead.clear()
            }
            cancelledAhead.add(requestId)
        }
    }

    fun remove(requestId: Long) = synchronized(lock) {
        pending.remove(requestId)
        Unit
    }

    /** Cancels and drains every pending request (engine detach). */
    fun cancelAll(): List<RequestState> = synchronized(lock) {
        val states = pending.values.toList()
        states.forEach { it.markCancelled() }
        pending.clear()
        cancelledAhead.clear()
        states
    }

    val pendingCount: Int
        get() = synchronized(lock) { pending.size }

    val cancelledAheadCount: Int
        get() = synchronized(lock) { cancelledAhead.size }

    companion object {
        const val CANCELLED_AHEAD_LIMIT = 4096
    }
}
