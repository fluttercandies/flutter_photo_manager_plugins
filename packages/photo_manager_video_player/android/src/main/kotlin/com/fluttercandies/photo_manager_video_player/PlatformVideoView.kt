package com.fluttercandies.photo_manager_video_player

import android.content.Context
import android.os.Build
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * A SurfaceView the player draws into directly. Unlike a texture, its frames
 * stay on their own display layer, so the system applies HDR handling to them.
 */
class PlatformVideoView(context: Context, private val player: GalleryVideoPlayer) : PlatformView {

    private val surfaceView = object : SurfaceView(context) {
        // Coming back from a covering route shows the view without a new surface.
        override fun onVisibilityChanged(changedView: View, visibility: Int) {
            super.onVisibilityChanged(changedView, visibility)
            if (visibility == View.VISIBLE && isShown) player.attachSurface(holder.surface)
        }
    }

    init {
        // The surface is destroyed in the background and recreated on return.
        surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) = player.attachSurface(holder.surface)

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

            override fun surfaceDestroyed(holder: SurfaceHolder) = player.detachSurface(holder.surface)
        })
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.N_MR1) {
            // Below Android 8 the video otherwise ends up behind the Flutter view.
            surfaceView.setZOrderMediaOverlay(true)
        }
    }

    override fun getView(): View = surfaceView

    override fun dispose() {
        player.detachSurface(surfaceView.holder.surface)
    }
}

/** Builds a [PlatformVideoView] for the `playerId` in the creation params. */
class PlatformVideoViewFactory(
    private val findPlayer: (Long) -> GalleryVideoPlayer?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val player = playerIdFrom(args)?.let(findPlayer)
        // A view outliving its player (disposed mid-build) shows nothing.
        return player?.let { PlatformVideoView(context, it) } ?: EmptyView(context)
    }

    private class EmptyView(context: Context) : PlatformView {
        private val view = View(context)

        override fun getView(): View = view

        override fun dispose() {}
    }
}

/** The player id in a view's creation params; small ids arrive as Int. */
internal fun playerIdFrom(args: Any?): Long? =
    ((args as? Map<*, *>)?.get("playerId") as? Number)?.toLong()
