package com.fluttercandies.photo_manager_native_image

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger

class RequestRegistryTest {
    private fun state(id: Long, sink: (Result<NativeImageReply?>) -> Unit = {}) = RequestState(id, sink)

    @Test
    fun finishDeliversExactlyOnce() {
        var replies = 0
        val s = state(1) { replies++ }
        assertTrue(s.finish(Result.success(null)))
        assertFalse(s.finish(Result.success(mapOf("pointer" to 1L))))
        assertFalse(s.finish(Result.failure(NativeImageError("decode_failed"))))
        assertEquals(1, replies)
        assertTrue(s.isDone)
    }

    @Test
    fun cancelBeforeAllocationMarksState() {
        val registry = RequestRegistry()
        val s = state(7)
        assertTrue(registry.register(s))
        registry.cancel(7)
        assertTrue(s.isCancelled)
        assertEquals(0, registry.cancelledAheadCount)
    }

    @Test
    fun cancelAheadOfRequestIsConsumedOnce() {
        val registry = RequestRegistry()
        registry.cancel(3)
        assertEquals(1, registry.cancelledAheadCount)
        assertFalse(registry.register(state(3)))
        assertEquals(0, registry.cancelledAheadCount)
        assertTrue(registry.register(state(3)))
    }

    @Test
    fun cancelAfterRemovalDoesNotResurrectRequest() {
        val registry = RequestRegistry()
        val s = state(9)
        assertTrue(registry.register(s))
        registry.remove(9)
        registry.cancel(9)
        assertFalse(s.isCancelled)
        assertEquals(0, registry.pendingCount)
    }

    @Test
    fun cancelledAheadSetIsBounded() {
        val registry = RequestRegistry()
        for (id in 0 until (RequestRegistry.CANCELLED_AHEAD_LIMIT + 5).toLong()) registry.cancel(id)
        assertTrue(registry.cancelledAheadCount <= RequestRegistry.CANCELLED_AHEAD_LIMIT)
    }

    @Test
    fun cancelAllDrainsPending() {
        val registry = RequestRegistry()
        val a = state(1)
        val b = state(2)
        registry.register(a)
        registry.register(b)
        val drained = registry.cancelAll()
        assertEquals(2, drained.size)
        assertTrue(a.isCancelled && b.isCancelled)
        assertEquals(0, registry.pendingCount)
    }

    @Test
    fun bufferProducedAfterDetachIsFreed() {
        val registry = RequestRegistry()
        val replies = mutableListOf<Result<NativeImageReply?>>()
        val s = state(11) { replies.add(it) }
        registry.register(s)
        // Engine detach settles the request before the worker hands back its buffer.
        registry.cancelAll().forEach { it.finish(Result.success(null)) }
        val freed = mutableListOf<Long>()
        val accepted = s.deliver(
            Result.success(mapOf("pointer" to 0xABCL, "width" to 1L, "height" to 1L, "rowBytes" to 4L)),
        ) { freed.add(it) }
        assertFalse(accepted)
        assertEquals(listOf(0xABCL), freed)
        assertEquals(1, replies.size)
        assertEquals(null, replies.single().getOrNull())
    }

    @Test
    fun acceptedBufferIsNotFreed() {
        val s = state(12)
        val freed = mutableListOf<Long>()
        assertTrue(s.deliver(Result.success(mapOf("pointer" to 0xDEFL))) { freed.add(it) })
        assertTrue(freed.isEmpty())
    }

    @Test
    fun rejectedErrorOrNullFreesNothing() {
        val s = state(13)
        s.finish(Result.success(null))
        val freed = mutableListOf<Long>()
        assertFalse(s.deliver(Result.failure(NativeImageError("decode_failed"))) { freed.add(it) })
        assertFalse(s.deliver(Result.success(null)) { freed.add(it) })
        assertTrue(freed.isEmpty())
    }

    @Test
    fun replyAfterDetachFreesTheBuffer() {
        val freed = mutableListOf<Long>()
        var replied = 0
        replyOrFree(Result.success(mapOf("pointer" to 0x77L)), attached = false, callback = { replied++ }) { freed.add(it) }
        assertEquals(0, replied)
        assertEquals(listOf(0x77L), freed)
    }

    @Test
    fun replyWhileAttachedIsDelivered() {
        val freed = mutableListOf<Long>()
        var replied = 0
        replyOrFree(Result.success(mapOf("pointer" to 0x78L)), attached = true, callback = { replied++ }) { freed.add(it) }
        assertEquals(1, replied)
        assertTrue(freed.isEmpty())
    }

    @Test
    fun replyAfterDetachWithoutBufferFreesNothing() {
        val freed = mutableListOf<Long>()
        replyOrFree(Result.success(null), attached = false, callback = {}) { freed.add(it) }
        replyOrFree(Result.failure(NativeImageError("not_found")), attached = false, callback = {}) { freed.add(it) }
        assertTrue(freed.isEmpty())
    }

    @Test
    fun concurrentFinishDeliversOnce() {
        val replies = AtomicInteger()
        val s = state(5) { replies.incrementAndGet() }
        val start = CountDownLatch(1)
        val threads = (0 until 16).map {
            Thread {
                start.await()
                s.finish(Result.success(null))
            }.apply { start() }
        }
        start.countDown()
        threads.forEach { it.join() }
        assertEquals(1, replies.get())
    }
}
