package com.fluttercandies.photo_manager_native_image

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ColorSpace
import android.net.Uri
import java.io.FileNotFoundException

/** Full-image decode for API 26–28, downsampled so the shorter side stays >= the target. */
object SampledBitmapDecoder {
    fun decode(resolver: ContentResolver, uri: Uri, targetShorter: Int): Bitmap? {
        // A bounds-only decode returns null on success; the result is in `bounds`.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        val stream = resolver.openInputStream(uri) ?: throw FileNotFoundException(uri.toString())
        stream.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inPreferredColorSpace = ColorSpace.get(ColorSpace.Named.SRGB)
            inSampleSize = ThumbnailMath.sampleSize(bounds.outWidth, bounds.outHeight, targetShorter)
        }
        return resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
    }
}
