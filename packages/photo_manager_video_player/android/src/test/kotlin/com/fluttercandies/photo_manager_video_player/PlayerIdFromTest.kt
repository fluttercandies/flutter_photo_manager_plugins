package com.fluttercandies.photo_manager_video_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlayerIdFromTest {
    @Test
    fun readsIntAndLongIds() {
        assertEquals(-1L, playerIdFrom(mapOf("playerId" to -1)))
        assertEquals(-5_000_000_000L, playerIdFrom(mapOf("playerId" to -5_000_000_000L)))
    }

    @Test
    fun missingOrMalformedParamsGiveNoId() {
        assertNull(playerIdFrom(null))
        assertNull(playerIdFrom(mapOf("playerId" to "1")))
        assertNull(playerIdFrom(listOf(1)))
    }
}
