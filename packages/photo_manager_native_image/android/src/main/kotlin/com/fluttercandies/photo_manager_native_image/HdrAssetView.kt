package com.fluttercandies.photo_manager_native_image

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.View
import android.widget.ImageView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.ExecutorService

/** Creates [HdrAssetView]s; [executor] is the single thread every view decodes on. */
class HdrAssetViewFactory(
    private val decoder: NativeImageDecoder,
    private val executor: ExecutorService,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val assetId = params?.get("assetId") as? String
        val size = (params?.get("size") as? Number)?.toInt() ?: 0
        return HdrAssetView(context, decoder, executor, assetId, size)
    }
}

/**
 * An `ImageView` that shows the image only when its decode carries a gain map
 * (API 34+); otherwise it stays transparent.
 */
private const val PROBE_SAMPLE = 16

class HdrAssetView(
    context: Context,
    private val decoder: NativeImageDecoder,
    executor: ExecutorService,
    assetId: String?,
    size: Int,
) : PlatformView {
    private val imageView = ImageView(context).apply { scaleType = ImageView.ScaleType.MATRIX }
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var disposed = false
    private var rotation = 0

    init {
        val id = assetId?.toLongOrNull()
        if (id != null && size > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            imageView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> applyMatrix() }
            try {
                executor.execute { decode(context, id, size) }
            } catch (_: Exception) {
                // The executor was shut down with the engine; the view stays transparent.
            }
        }
    }

    override fun getView(): View = imageView

    override fun dispose() {
        disposed = true
        val bitmap = (imageView.drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap
        imageView.setImageDrawable(null)
        bitmap?.recycle()
    }

    private fun decode(context: Context, id: Long, size: Int) {
        if (disposed) return
        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
        val resolver = context.contentResolver
        try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return
            // A tiny decode tells whether the file carries a gain map before paying for the full one.
            val probe = BitmapFactory.Options().apply { inSampleSize = PROBE_SAMPLE }
            val small = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, probe) } ?: return
            val hasGainmap = small.hasGainmap()
            small.recycle()
            if (disposed || !hasGainmap) return
            val options = BitmapFactory.Options().apply {
                inSampleSize = ThumbnailMath.sampleSize(bounds.outWidth, bounds.outHeight, size)
            }
            val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) } ?: return
            val bitmap = fitToSize(decoded, size)
            if (disposed || !bitmap.hasGainmap()) {
                bitmap.recycle()
                return
            }
            val rotation = decoder.legacyImageMetadata(uri).third
            mainHandler.post { show(bitmap, rotation) }
        } catch (_: Exception) {
            // Any failure leaves the view transparent.
        }
    }

    /**
     * Power-of-two sampling can leave the shorter side up to twice [size]. On API 35+ the
     * bitmap is scaled down to [size] with its gain map; if the gain map would be lost, the
     * sampled bitmap is kept as is.
     */
    private fun fitToSize(bitmap: Bitmap, size: Int): Bitmap {
        val shorter = minOf(bitmap.width, bitmap.height)
        if (shorter <= size || Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return bitmap
        val scale = size.toFloat() / shorter
        val scaled = Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * scale).toInt().coerceAtLeast(1),
            (bitmap.height * scale).toInt().coerceAtLeast(1),
            true,
        )
        if (scaled === bitmap) return bitmap
        if (!scaled.hasGainmap()) {
            scaled.recycle()
            return bitmap
        }
        bitmap.recycle()
        return scaled
    }

    private fun show(bitmap: Bitmap, degrees: Int) {
        if (disposed) {
            bitmap.recycle()
            return
        }
        rotation = degrees
        imageView.setImageBitmap(bitmap)
        applyMatrix()
    }

    private fun applyMatrix() {
        val bitmap = (imageView.drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap ?: return
        val width = imageView.width
        val height = imageView.height
        if (width <= 0 || height <= 0) return
        val matrix = Matrix()
        matrix.setValues(ThumbnailMath.coverMatrixValues(bitmap.width, bitmap.height, rotation, width, height))
        imageView.imageMatrix = matrix
    }
}
