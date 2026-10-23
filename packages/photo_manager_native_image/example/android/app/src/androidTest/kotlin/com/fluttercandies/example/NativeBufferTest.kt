package com.fluttercandies.example

import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.fluttercandies.photo_manager_native_image.NativeBuffer
import com.fluttercandies.photo_manager_native_image.NativeImageDecoder
import com.fluttercandies.photo_manager_native_image.NativeImageException
import com.fluttercandies.photo_manager_native_image.ThumbnailMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeBufferTest {
    @Test
    fun mallocWrapFreeRoundTrip() {
        val pointer = NativeBuffer.allocate(64)
        assertNotEquals(0L, pointer)
        val bitmap = Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(0xFF3366CC.toInt())
        bitmap.copyPixelsToBuffer(NativeBuffer.wrap(pointer, 64))
        val view = NativeBuffer.wrap(pointer, 64)
        // ARGB_8888 stores R,G,B,A in memory order, what Flutter's rgba8888 expects.
        assertEquals(0x33, view.get(0).toInt() and 0xFF)
        assertEquals(0x66, view.get(1).toInt() and 0xFF)
        assertEquals(0xCC, view.get(2).toInt() and 0xFF)
        assertEquals(0xFF, view.get(3).toInt() and 0xFF)
        NativeBuffer.free(pointer)
        bitmap.recycle()
    }

    @Test
    fun allocateRejectsNonPositiveSizes() {
        assertEquals(0L, NativeBuffer.allocate(0))
        assertEquals(0L, NativeBuffer.allocate(-8))
    }

    @Test
    fun rotationMatrixTurnsLandscapeIntoPortrait() {
        val source = Bitmap.createBitmap(4, 2, Bitmap.Config.ARGB_8888)
        val degrees = ThumbnailMath.rotationToApply(90, 4000, 2000, source.width, source.height)
        assertEquals(90, degrees)
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        val rotated = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
        assertEquals(2, rotated.width)
        assertEquals(4, rotated.height)
    }

    @Test
    fun decoderReportsNotFoundForUnknownIds() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val decoder = NativeImageDecoder(context)
        for (id in listOf("not-a-number", Long.MAX_VALUE.toString())) {
            try {
                decoder.decode(id, 64, 64, isVideo = false)
                fail("expected not_found for $id")
            } catch (e: NativeImageException) {
                assertEquals("not_found", e.code)
            }
        }
    }

    @Test
    fun apiBranchMatchesDevice() {
        // Documents which decode path this device exercises.
        val legacy = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
        assertTrue(Build.VERSION.SDK_INT >= 26)
        assertEquals(legacy, Build.VERSION.SDK_INT in 26..28)
    }
}
