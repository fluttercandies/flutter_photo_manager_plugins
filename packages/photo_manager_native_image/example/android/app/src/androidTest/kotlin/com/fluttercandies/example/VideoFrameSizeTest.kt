package com.fluttercandies.example

import android.content.ContentUris
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Environment
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.fluttercandies.photo_manager_native_image.NativeImageDecoder
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Video thumbnails reach the requested shorter side on every API level. */
@RunWith(AndroidJUnit4::class)
class VideoFrameSizeTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val decoder = NativeImageDecoder(context)
    private val created = mutableListOf<Pair<File, Uri>>()

    @After
    fun tearDown() {
        created.forEach { (file, uri) ->
            context.contentResolver.delete(uri, null, null)
            file.delete()
        }
    }

    private fun video(asset: String): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        dir.mkdirs()
        val file = File(dir, "pmni_${System.nanoTime()}.mp4")
        instrumentation.context.assets.open(asset).use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
        val latch = CountDownLatch(1)
        var uri: Uri? = null
        MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), null) { _, scanned ->
            uri = scanned
            latch.countDown()
        }
        assertTrue("media scan timed out", latch.await(20, TimeUnit.SECONDS))
        created.add(file to uri!!)
        return ContentUris.parseId(uri).toString()
    }

    private fun assertSize(id: String, size: Int, landscape: Boolean) {
        val bitmap = decoder.decode(id, size, size, isVideo = true)
        val d = "${bitmap.width}x${bitmap.height} for $size"
        assertEquals(d, size, minOf(bitmap.width, bitmap.height))
        assertEquals(d, landscape, bitmap.width > bitmap.height)
    }

    @Test
    fun landscapeVideoReachesTheShorterSide() {
        val id = video("wide_1080p.mp4")
        listOf(96, 300, 384, 512, 720, 1080).forEach { assertSize(id, it, landscape = true) }
    }

    @Test
    fun rotatedVideoReachesTheShorterSide() {
        val id = video("wide_1080p_rot90.mp4")
        listOf(300, 512, 1080).forEach { assertSize(id, it, landscape = false) }
    }
}
