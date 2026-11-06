package com.voiceagent.voice_agent.location

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Row ids: a report made in the same millisecond as its cause sorts after it. */
class Uuid7Test {
    private val shape = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

    @Test
    fun idsInOneMillisecondRiseStrictly() {
        val ms = 1_762_400_000_000L
        val ids = List(5_000) { Uuid7.next(ms) }
        for (id in ids) assertTrue(id, shape.matches(id))
        for (i in 1 until ids.size) assertTrue("${ids[i - 1]} !< ${ids[i]}", ids[i - 1] < ids[i])
    }

    @Test
    fun aClockGoingBackDoesNotBreakTheOrder() {
        val first = Uuid7.next(1_900_000_000_000L)
        val second = Uuid7.next(1_800_000_000_000L)
        assertTrue(first < second)
    }

    @Test
    fun theTimeIsTheFirst48Bits() {
        val ms = 2_000_000_000_000L
        val id = Uuid7.next(ms)
        assertEquals(ms, (id.substring(0, 8) + id.substring(9, 13)).toLong(16))
    }
}
