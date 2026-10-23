package com.fluttercandies.photo_manager_video_player

import android.content.ContentUris
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.Surface
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry
import java.io.FileNotFoundException

/**
 * Owns one ExoPlayer fed straight from a MediaStore `content://` URI, so
 * nothing is copied into the app sandbox. With a [surface] it draws into a
 * Flutter texture; without one it waits for a [PlatformVideoView] to attach a
 * SurfaceView, which keeps HDR video on its own display layer.
 */
class GalleryVideoPlayer(
    context: Context,
    messenger: BinaryMessenger,
    private val surface: TextureRegistry.SurfaceProducer?,
    val playerId: Long,
    private val assetId: String,
    initialLooping: Boolean,
    initialVolume: Double,
) {
    private val events =
        EventChannel(messenger, "${PhotoManagerVideoPlayerPlugin.CHANNEL_NAME}/events/$playerId")
    private var sink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private var prepared = false
    private var released = false
    private var initializedEventSent = false

    private val playerListener = object : Player.Listener {
        override fun onVideoSizeChanged(videoSize: VideoSize) {
            if (videoSize.width <= 0 || videoSize.height <= 0) return
            surface?.setSize(videoSize.width, videoSize.height)
            emit(
                "videoSize",
                mapOf(
                    "width" to videoSize.width,
                    "height" to videoSize.height,
                    "rotationDegrees" to rotationForDart(
                        exoPlayer.videoFormat?.rotationDegrees ?: 0,
                        // The decoder rotates frames written to a SurfaceView.
                        surface?.handlesCropAndRotation() ?: true,
                    ),
                ),
            )
        }

        override fun onRenderedFirstFrame() {
            emit("firstFrame")
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            when (playbackState) {
                Player.STATE_READY -> emitInitializedOnce()
                Player.STATE_ENDED -> {
                    stopPositionUpdates()
                    emit("completed")
                }
            }
            emit("buffering", mapOf("isBuffering" to (playbackState == Player.STATE_BUFFERING)))
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            emit("playing", mapOf("isPlaying" to isPlaying))
            if (isPlaying) startPositionUpdates() else stopPositionUpdates()
        }

        override fun onPlayerError(error: PlaybackException) {
            val (code, message) = mapPlaybackError(error.errorCode, error)
            emitError(code, message)
        }
    }

    private val audioAttributes =
        AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build()

    private val exoPlayer: ExoPlayer = ExoPlayer.Builder(context)
        .setMediaSourceFactory(
            DefaultMediaSourceFactory(context).setLoadErrorHandlingPolicy(NoRetryForMissingAsset),
        )
        .build()
        .apply {
            volume = initialVolume.toFloat().coerceIn(0f, 1f)
            applyAudioFocus()
            repeatMode = if (initialLooping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            addListener(playerListener)
            if (surface != null) setVideoSurface(surface.surface)
        }

    init {
        // Android can reclaim the surface while the app is backgrounded; the
        // player has to be re-attached to the new one on the way back.
        surface?.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                if (!released) exoPlayer.setVideoSurface(surface.surface)
            }

            override fun onSurfaceCleanup() {
                if (!released) exoPlayer.setVideoSurface(null)
            }
        })

        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                this@GalleryVideoPlayer.sink = sink
                prepare()
            }

            override fun onCancel(arguments: Any?) {
                this@GalleryVideoPlayer.sink = null
            }
        })
    }

    /** Hands the MediaStore URI to ExoPlayer. Idempotent. */
    fun prepare() {
        if (prepared || released) return
        prepared = true
        val id = assetId.toLongOrNull()
        if (id == null) {
            emitError("assetNotFound", "'$assetId' is not a MediaStore id.")
            return
        }
        val uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
        exoPlayer.setMediaItem(MediaItem.fromUri(uri))
        exoPlayer.prepare()
    }

    /** Draws into a platform view's surface; called each time it is (re)created. */
    fun attachSurface(target: Surface) {
        if (released || !target.isValid) return
        exoPlayer.setVideoSurface(target)
        // Android 9 decoders keep the old output when a surface arrives while
        // paused, leaving the view blank until a seek flushes them.
        if (Build.VERSION.SDK_INT == Build.VERSION_CODES.P && !exoPlayer.playWhenReady) {
            val position = exoPlayer.currentPosition
            exoPlayer.seekTo(if (position == 0L) 1L else position)
        }
    }

    /** Stops drawing into [target], unless another view has already taken over. */
    fun detachSurface(target: Surface) {
        if (!released) exoPlayer.clearVideoSurface(target)
    }

    fun play() {
        // play() does nothing once playback ended, so a replay has to rewind.
        if (exoPlayer.playbackState == Player.STATE_ENDED) exoPlayer.seekTo(0)
        exoPlayer.play()
    }

    fun pause() = exoPlayer.pause()

    fun seekTo(positionMs: Long) {
        exoPlayer.seekTo(positionMs)
        // The position poller only runs while playing, so a paused seek would
        // otherwise never reach the UI.
        emit("position", mapOf("positionMs" to positionMs))
    }

    fun setVolume(volume: Double) {
        exoPlayer.volume = volume.toFloat().coerceIn(0f, 1f)
        exoPlayer.applyAudioFocus()
    }

    /**
     * Audible playback takes audio focus and pauses other audio; a muted
     * player must not, or a silent preview would stop the user's music.
     */
    private fun ExoPlayer.applyAudioFocus() = setAudioAttributes(audioAttributes, volume > 0f)

    fun setLooping(looping: Boolean) {
        exoPlayer.repeatMode = if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
    }

    fun release() {
        if (released) return
        released = true
        stopPositionUpdates()
        exoPlayer.removeListener(playerListener)
        exoPlayer.release()
        surface?.release()
        events.setStreamHandler(null)
        sink = null
    }

    private fun emitInitializedOnce() {
        if (initializedEventSent) return
        val duration = exoPlayer.duration
        if (duration == C.TIME_UNSET) return
        initializedEventSent = true
        emit("initialized", mapOf("durationMs" to duration))
    }

    private val positionRunnable = object : Runnable {
        override fun run() {
            emit("position", mapOf("positionMs" to exoPlayer.currentPosition))
            mainHandler.postDelayed(this, POSITION_POLL_INTERVAL_MS)
        }
    }

    private fun startPositionUpdates() {
        mainHandler.removeCallbacks(positionRunnable)
        mainHandler.post(positionRunnable)
    }

    private fun stopPositionUpdates() = mainHandler.removeCallbacks(positionRunnable)

    private fun emit(event: String, extra: Map<String, Any?> = emptyMap()) {
        sink?.success(mapOf("event" to event) + extra)
    }

    private fun emitError(code: String, message: String) =
        emit("error", mapOf("code" to code, "message" to message))

    companion object {
        private const val POSITION_POLL_INTERVAL_MS = 200L
    }
}

/**
 * (code, message) for a [PlaybackException]'s code and exception, matching `AssetEntityVideoErrorCode`
 * on the Dart side. media3 wraps the platform exception, so the whole cause
 * chain and the error code are checked.
 */
internal fun mapPlaybackError(errorCode: Int, error: Throwable): Pair<String, String> {
    val causes = generateSequence(error) { it.cause }
    return when {
        errorCode == PlaybackException.ERROR_CODE_IO_NO_PERMISSION ||
            causes.any { it is SecurityException } ->
            "permissionDenied" to "No access to this asset."
        errorCode == PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND ||
            causes.any { it is FileNotFoundException } ->
            "assetNotFound" to "Asset is no longer in the library."
        else -> "playbackFailed" to (error.message ?: "Playback failed.")
    }
}

/** A missing or forbidden asset will not appear on retry, so it fails at once. */
private object NoRetryForMissingAsset : DefaultLoadErrorHandlingPolicy() {
    override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
        val causes = generateSequence<Throwable>(loadErrorInfo.exception) { it.cause }
        if (causes.any { it is FileNotFoundException || it is SecurityException }) return C.TIME_UNSET
        return super.getRetryDelayMsFor(loadErrorInfo)
    }
}

/**
 * Rotation the Dart view still has to apply. The SurfaceTexture backend already
 * rotates frames by the stream metadata; the ImageReader backend (API 29+) does not.
 */
internal fun rotationForDart(formatRotationDegrees: Int, surfaceHandlesRotation: Boolean): Int =
    if (surfaceHandlesRotation) 0 else formatRotationDegrees
