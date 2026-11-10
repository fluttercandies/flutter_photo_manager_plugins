package com.fluttercandies.photo_manager_video_player

import org.junit.Assert.assertEquals
import org.junit.Test

class RotationForDartTest {
    @Test
    fun imageReaderBackendLeavesRotationToDart() {
        for (degrees in listOf(0, 90, 180, 270)) {
            assertEquals(degrees, rotationForDart(degrees, surfaceHandlesRotation = false))
        }
    }

    @Test
    fun surfaceTextureBackendAlreadyRotates() {
        for (degrees in listOf(0, 90, 180, 270)) {
            assertEquals(0, rotationForDart(degrees, surfaceHandlesRotation = true))
        }
    }
}
