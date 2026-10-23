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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** MediaStore decode paths used on API 26–28, on real sample media. */
@Suppress("DEPRECATION")
@RunWith(AndroidJUnit4::class)
class LegacyDecodeTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val decoder = NativeImageDecoder(context)
    private val created = mutableListOf<Pair<File, Uri>>()

    @Before
    fun setUp() {
        assumeTrue(Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)
    }

    @After
    fun tearDown() {
        created.forEach { (file, uri) ->
            context.contentResolver.delete(uri, null, null)
            file.delete()
        }
    }

    private fun scan(file: File): Uri {
        val latch = CountDownLatch(1)
        var result: Uri? = null
        MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), null) { _, uri ->
            result = uri
            latch.countDown()
        }
        assertTrue("media scan timed out", latch.await(20, TimeUnit.SECONDS))
        return result!!.also { created.add(file to it) }
    }

    /**
     * A 400x300 landscape JPEG registered in MediaStore. `rotated` sets the
     * orientation column the decoder reads (90), as the scanner does for EXIF 6.
     */
    private fun landscapeJpeg(rotated: Boolean): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        dir.mkdirs()
        val file = File(dir, "pmni_${System.nanoTime()}.jpg")
        val bitmap = Bitmap.createBitmap(400, 300, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(0xFF2E7D32.toInt())
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        bitmap.recycle()
        val uri = scan(file)
        if (rotated) {
            val values = ContentValues().apply { put(MediaStore.Images.ImageColumns.ORIENTATION, 90) }
            assertEquals(1, context.contentResolver.update(uri, values, null, null))
        }
        return ContentUris.parseId(uri).toString()
    }

    private fun landscapeVideoRotated90(): String = video("landscape_rot90.mp4")

    private fun video(asset: String): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        dir.mkdirs()
        val file = File(dir, "pmni_${System.nanoTime()}.mp4")
        instrumentation.context.assets.open(asset).use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
        return ContentUris.parseId(scan(file)).toString()
    }

    /**
     * The API 28 emulator's software decoder sometimes returns an all-black
     * frame for a valid clip (seen on both the MINI_KIND and retriever paths,
     * never on API 26). Retry so the rotation assertions test rotation.
     */
    private fun decodeVideo(id: String, size: Int): Bitmap {
        var bitmap = decoder.decode(id, size, size, isVideo = true)
        repeat(3) {
            if (!isAllBlack(bitmap)) return bitmap
            bitmap = decoder.decode(id, size, size, isVideo = true)
        }
        // A black MINI_KIND thumbnail is stored by MediaStore, so retrying cannot help;
        // the package returns it untouched, so there is no rotation left to check.
        assumeFalse("emulator stored an all-black system thumbnail", isAllBlack(bitmap))
        return bitmap
    }

    private fun isAllBlack(bitmap: Bitmap): Boolean =
        listOf(0.1f, 0.5f, 0.9f).all { fy ->
            listOf(0.1f, 0.5f, 0.9f).all { fx ->
                bitmap.getPixel(((bitmap.width - 1) * fx).toInt(), ((bitmap.height - 1) * fy).toInt()) and 0xFFFFFF == 0
            }
        }

    /** A 400x300 JPEG, red on top and blue at the bottom, with [orientation] in MediaStore. */
    private fun splitJpeg(orientation: Int): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        dir.mkdirs()
        val file = File(dir, "pmni_${System.nanoTime()}.jpg")
        val bitmap = Bitmap.createBitmap(400, 300, Bitmap.Config.ARGB_8888)
        android.graphics.Canvas(bitmap).apply {
            drawRect(0f, 0f, 400f, 150f, android.graphics.Paint().apply { color = 0xFFFF0000.toInt() })
            drawRect(0f, 150f, 400f, 300f, android.graphics.Paint().apply { color = 0xFF0000FF.toInt() })
        }
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it) }
        bitmap.recycle()
        val uri = scan(file)
        if (orientation != 0) {
            val values = ContentValues().apply { put(MediaStore.Images.ImageColumns.ORIENTATION, orientation) }
            assertEquals(1, context.contentResolver.update(uri, values, null, null))
        }
        return ContentUris.parseId(uri).toString()
    }

    /** 'R' or 'B' for the dominant channel at a relative position. */
    private fun colorAt(bitmap: Bitmap, fx: Float, fy: Float): Char {
        val p = bitmap.getPixel(((bitmap.width - 1) * fx).toInt(), ((bitmap.height - 1) * fy).toInt())
        val r = (p shr 16) and 0xFF
        val b = p and 0xFF
        return if (r > b) 'R' else 'B'
    }

    /** Red-top/blue-bottom source shown rotated 180°: blue on top, landscape. */
    private fun describe(bitmap: Bitmap): String =
        "${bitmap.width}x${bitmap.height} " + listOf(0.05f, 0.3f, 0.7f, 0.95f).joinToString("/") { y ->
            "%06x".format(bitmap.getPixel((bitmap.width - 1) / 2, ((bitmap.height - 1) * y).toInt()) and 0xFFFFFF)
        }

    private fun assertUpsideDown(bitmap: Bitmap) {
        val d = describe(bitmap)
        assertTrue("expected landscape, got $d", bitmap.width > bitmap.height)
        assertEquals(d, 'B', colorAt(bitmap, 0.5f, 0.1f))
        assertEquals(d, 'R', colorAt(bitmap, 0.5f, 0.9f))
    }

    /** Red-top/blue-bottom source rotated 90° clockwise: red on the right, portrait. */
    private fun assertTurnedClockwise(bitmap: Bitmap) {
        val d = describe(bitmap)
        assertTrue("expected portrait, got $d", bitmap.height > bitmap.width)
        assertEquals(d, 'B', colorAt(bitmap, 0.1f, 0.5f))
        assertEquals(d, 'R', colorAt(bitmap, 0.9f, 0.5f))
    }

    @Test
    fun imageThumbnailIsUpright() {
        val id = landscapeJpeg(rotated = true)
        val bitmap = decoder.decode(id, 128, 128, isVideo = false)
        assertTrue("expected portrait, got ${bitmap.width}x${bitmap.height}", bitmap.height > bitmap.width)
        assertEquals(128, minOf(bitmap.width, bitmap.height))
        assertEquals(Bitmap.Config.ARGB_8888, bitmap.config)
    }

    @Test
    fun imageFullDecodeIsUpright() {
        // Above the MINI_KIND size, so this goes through BitmapFactory.
        val id = landscapeJpeg(rotated = true)
        val bitmap = decoder.decode(id, 512, 512, isVideo = false)
        assertEquals(300, bitmap.width)
        assertEquals(400, bitmap.height)
    }

    @Test
    fun imageWithoutRotationStaysLandscape() {
        val id = landscapeJpeg(rotated = false)
        val bitmap = decoder.decode(id, 512, 512, isVideo = false)
        assertEquals(400, bitmap.width)
        assertEquals(300, bitmap.height)
    }

    @Test
    fun videoThumbnailIsUpright() {
        val id = landscapeVideoRotated90()
        val bitmap = decodeVideo(id, 96)
        assertNotNull(bitmap)
        assertTrue("expected portrait, got ${bitmap.width}x${bitmap.height}", bitmap.height > bitmap.width)
    }

    @Test
    fun videoAboveMiniKindSizeIsDecodedUpright() {
        val bitmap = decodeVideo(landscapeVideoRotated90(), 512)
        assertTrue("expected portrait, got ${bitmap.width}x${bitmap.height}", bitmap.height > bitmap.width)
    }

    @Test
    fun video180IsNotRotatedTwice() {
        assertUpsideDown(decodeVideo(video("split_rot180.mp4"), 96))
    }

    @Test
    fun video90TurnsClockwise() {
        assertTurnedClockwise(decodeVideo(video("split_rot90.mp4"), 96))
    }

    @Test
    fun largeVideo180IsNotRotatedTwice() {
        assertUpsideDown(decodeVideo(video("split_rot180.mp4"), 512))
    }

    @Test
    fun image180ThumbnailIsNotRotatedTwice() {
        assertUpsideDown(decoder.decode(splitJpeg(180), 128, 128, isVideo = false))
    }

    @Test
    fun image180FullDecodeIsNotRotatedTwice() {
        assertUpsideDown(decoder.decode(splitJpeg(180), 512, 512, isVideo = false))
    }

    @Test
    fun image90TurnsClockwise() {
        assertTurnedClockwise(decoder.decode(splitJpeg(90), 128, 128, isVideo = false))
    }
}
