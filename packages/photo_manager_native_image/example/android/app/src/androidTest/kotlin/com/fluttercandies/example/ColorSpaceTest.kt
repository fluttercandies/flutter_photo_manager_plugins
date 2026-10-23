package com.fluttercandies.example

import android.content.ContentUris
import android.content.ContentValues
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.fluttercandies.photo_manager_native_image.NativeImageDecoder
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/** Flutter reads the RGBA bytes as sRGB, so a Display P3 photo must arrive converted. */
@Suppress("DEPRECATION")
@RunWith(AndroidJUnit4::class)
class ColorSpaceTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val decoder = NativeImageDecoder(context)
    private val created = mutableListOf<Uri>()
    private val files = mutableListOf<File>()

    @After
    fun tearDown() {
        created.forEach { context.contentResolver.delete(it, null, null) }
        files.forEach { it.delete() }
    }

    /** `p3_red.jpg`: Display P3 (231, 60, 40), which is sRGB (250, 31, 14). */
    private fun insertP3Red(): String {
        val asset = instrumentation.context.assets
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "pmni_p3_${System.nanoTime()}.jpg")
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            }
            val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)!!
            context.contentResolver.openOutputStream(uri)!!.use { out ->
                asset.open("p3_red.jpg").use { it.copyTo(out) }
            }
            uri
        } else {
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            dir.mkdirs()
            val file = File(dir, "pmni_p3_${System.nanoTime()}.jpg").also { files.add(it) }
            asset.open("p3_red.jpg").use { input -> file.outputStream().use { input.copyTo(it) } }
            scan(file)
        }
        created.add(uri)
        return ContentUris.parseId(uri).toString()
    }

    private fun scan(file: File): Uri {
        val latch = CountDownLatch(1)
        var result: Uri? = null
        MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), null) { _, uri ->
            result = uri
            latch.countDown()
        }
        assertTrue("media scan timed out", latch.await(20, TimeUnit.SECONDS))
        return result!!
    }

    /** Raw bytes at the centre; `getPixel` would convert to sRGB and hide the bug. */
    private fun centreBytes(bitmap: Bitmap): Triple<Int, Int, Int> {
        val buffer = ByteBuffer.allocate(bitmap.byteCount)
        bitmap.copyPixelsToBuffer(buffer)
        val o = (bitmap.height / 2) * bitmap.rowBytes + (bitmap.width / 2) * 4
        return Triple(buffer[o].toInt() and 0xFF, buffer[o + 1].toInt() and 0xFF, buffer[o + 2].toInt() and 0xFF)
    }

    private fun assertSrgbRed(size: Int) {
        val bitmap = decoder.decode(insertP3Red(), size, size, isVideo = false)
        val (r, g, b) = centreBytes(bitmap)
        val message = "size $size: ($r, $g, $b) in ${bitmap.colorSpace}"
        assertTrue(message, abs(r - 250) <= 6 && abs(g - 31) <= 8 && abs(b - 14) <= 8)
    }

    @Test
    fun gridThumbnailIsSrgb() = assertSrgbRed(128)

    @Test
    fun largeThumbnailIsSrgb() = assertSrgbRed(1024)
}
