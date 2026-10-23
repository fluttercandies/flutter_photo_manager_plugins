package com.fluttercandies.photo_manager_native_image

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class PhotoManagerNativeImagePlugin : FlutterPlugin, NativeImageHostApi {
    private lateinit var decoder: NativeImageDecoder
    private val registry = RequestRegistry()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** One engine attachment; a plugin instance can be attached again later. */
    private class Attachment {
        val executor: ExecutorService =
            Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors() / 2 + 1)

        // Read and written on the main thread only.
        var attached = true
    }

    private var attachment: Attachment? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        decoder = NativeImageDecoder(binding.applicationContext)
        attachment = Attachment()
        NativeImageHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeImageHostApi.setUp(binding.binaryMessenger, null)
        registry.cancelAll().forEach { it.finish(Result.success(null)) }
        attachment?.let {
            it.attached = false
            it.executor.shutdownNow()
        }
        attachment = null
    }

    override fun requestImage(
        assetId: String,
        requestId: Long,
        width: Long,
        height: Long,
        isVideo: Boolean,
        allowNetwork: Boolean,
        callback: (Result<NativeImageReply?>) -> Unit,
    ) {
        val current = attachment ?: return callback(Result.success(null))
        // Replies must be posted from the main thread. The engine drops a reply
        // sent after it detached, so a buffer in such a reply is freed here.
        val state = RequestState(requestId) { result ->
            mainHandler.post {
                replyOrFree(result, current.attached, callback, NativeBuffer::free)
            }
        }
        if (!registry.register(state)) {
            state.finish(Result.success(null))
            return
        }
        try {
            current.executor.execute {
                try {
                    val result = produce(state, assetId, width.toInt(), height.toInt(), isVideo)
                    registry.remove(requestId)
                    state.deliver(result, NativeBuffer::free)
                } catch (t: Throwable) {
                    // An uncaught error on a pool thread would kill the
                    // process; a request must still get its one reply.
                    registry.remove(requestId)
                    state.finish(Result.failure(NativeImageError("decode_failed", t.toString())))
                }
            }
        } catch (_: Exception) {
            registry.remove(requestId)
            state.finish(Result.success(null))
        }
    }

    override fun cancelRequest(requestId: Long) {
        registry.cancel(requestId)
    }

    private fun produce(
        state: RequestState, assetId: String, width: Int, height: Int, isVideo: Boolean,
    ): Result<NativeImageReply?> {
        if (state.isCancelled) return Result.success(null)
        val bitmap = try {
            decoder.decode(assetId, width, height, isVideo)
        } catch (e: NativeImageException) {
            return Result.failure(NativeImageError(e.code, e.message))
        }
        if (state.isCancelled) {
            bitmap.recycle()
            return Result.success(null)
        }
        // No cancel checks past this point: the buffer is Dart's to free.
        return try {
            Result.success(copyToNativeBuffer(bitmap))
        } catch (e: Exception) {
            Result.failure(NativeImageError("decode_failed", e.toString()))
        } finally {
            bitmap.recycle()
        }
    }

    private fun copyToNativeBuffer(bitmap: Bitmap): NativeImageReply {
        val rowBytes = bitmap.rowBytes
        val size = rowBytes.toLong() * bitmap.height
        val pointer = NativeBuffer.allocate(size)
        if (pointer == 0L) throw IllegalStateException("malloc($size) failed")
        try {
            bitmap.copyPixelsToBuffer(NativeBuffer.wrap(pointer, size))
        } catch (e: Exception) {
            NativeBuffer.free(pointer)
            throw e
        }
        return mapOf(
            "pointer" to pointer,
            "width" to bitmap.width.toLong(),
            "height" to bitmap.height.toLong(),
            "rowBytes" to rowBytes.toLong(),
        )
    }
}
