package com.fluttercandies.example

import android.graphics.Bitmap
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.fluttercandies.photo_manager_native_image.SampledBitmapDecoder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class SampledBitmapDecoderTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private fun jpeg(width: Int, height: Int): Uri {
        val file = File(context.cacheDir, "sampled_${width}x$height.jpg")
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(0xFF336699.toInt())
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        bitmap.recycle()
        return Uri.fromFile(file)
    }

    @Test
    fun decodesAValidImageWithSampling() {
        val bitmap = SampledBitmapDecoder.decode(context.contentResolver, jpeg(2000, 1500), 320)
        assertNotNull(bitmap)
        // 1500 / 4 = 375 >= 320, 1500 / 8 < 320.
        assertEquals(500, bitmap!!.width)
        assertEquals(375, bitmap.height)
    }

    @Test
    fun decodesWithoutSamplingWhenAlreadySmall() {
        val bitmap = SampledBitmapDecoder.decode(context.contentResolver, jpeg(400, 300), 320)
        assertNotNull(bitmap)
        assertEquals(400, bitmap!!.width)
    }

    @Test(expected = java.io.FileNotFoundException::class)
    fun missingFileIsNotFound() {
        SampledBitmapDecoder.decode(
            context.contentResolver,
            Uri.fromFile(File(context.cacheDir, "missing.jpg")),
            320,
        )
    }
}
