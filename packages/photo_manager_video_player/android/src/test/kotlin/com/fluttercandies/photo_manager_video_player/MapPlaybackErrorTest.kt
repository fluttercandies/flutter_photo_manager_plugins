package com.fluttercandies.photo_manager_video_player

import androidx.media3.common.PlaybackException
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.FileNotFoundException
import java.io.IOException

/** media3 wraps the platform exception, so the code must not depend on the direct cause. */
class MapPlaybackErrorTest {
    private fun map(cause: Throwable, code: Int = PlaybackException.ERROR_CODE_UNSPECIFIED) =
        mapPlaybackError(code, RuntimeException("PlaybackException", cause)).first

    @Test
    fun aWrappedFileNotFoundIsAssetNotFound() {
        val wrapped = IOException("ContentDataSourceException", FileNotFoundException("gone"))
        assertEquals("assetNotFound", map(wrapped))
        assertEquals(
            "assetNotFound",
            map(IOException(), PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND),
        )
    }

    @Test
    fun aWrappedSecurityExceptionIsPermissionDenied() {
        val wrapped = IOException("UnexpectedLoaderException", SecurityException("denied"))
        assertEquals("permissionDenied", map(wrapped))
        assertEquals(
            "permissionDenied",
            map(IOException(), PlaybackException.ERROR_CODE_IO_NO_PERMISSION),
        )
    }

    @Test
    fun anythingElseIsPlaybackFailed() {
        assertEquals("playbackFailed", map(IllegalStateException("decoder")))
    }
}
