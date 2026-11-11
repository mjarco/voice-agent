package com.voiceagent.voice_agent.location

import com.voiceagent.voice_agent.location.Motion.SETTLE_MS
import com.voiceagent.voice_agent.location.Motion.State
import com.voiceagent.voice_agent.location.Motion.onTransition
import com.voiceagent.voice_agent.location.Motion.shouldSettle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Sampling by motion: transitions switch the readings, `still` settles after a while (ADR-PLATFORM-014). */
class MotionTest {
    private val now = 1_800_000_000_000L
    private val minute = 60_000L

    @Test
    fun eachMovingActivityHasItsInterval() {
        assertEquals(10, Motion.intervalSeconds(Motion.IN_VEHICLE))
        assertEquals(15, Motion.intervalSeconds(Motion.ON_BICYCLE))
        assertEquals(30, Motion.intervalSeconds(Motion.WALKING))
        assertEquals(30, Motion.intervalSeconds(Motion.RUNNING))
        assertEquals(null, Motion.intervalSeconds(Motion.STILL))
        assertEquals(null, Motion.intervalSeconds(null))
    }

    @Test
    fun startingToMoveMakesReadingsFrequentAtOnce() {
        val state = onTransition(State(), Motion.IN_VEHICLE, now)
        assertEquals(State(frequent = true, activity = Motion.IN_VEHICLE, atMs = now, intervalS = 10), state)
    }

    @Test
    fun anotherMotionChangesTheInterval() {
        val driving = onTransition(State(), Motion.IN_VEHICLE, now)
        val walking = onTransition(driving, Motion.WALKING, now + minute)
        assertTrue(walking.frequent)
        assertEquals(30, walking.intervalS)
    }

    @Test
    fun stillKeepsTheReadingsFrequentUntilItSettles() {
        val driving = onTransition(State(), Motion.IN_VEHICLE, now)
        val stopped = onTransition(driving, Motion.STILL, now + minute)
        assertTrue(stopped.frequent)
        assertEquals(10, stopped.intervalS)
        assertFalse(shouldSettle(stopped, now + minute + SETTLE_MS - 1))
        assertTrue(shouldSettle(stopped, now + minute + SETTLE_MS))
    }

    @Test
    fun aMotionBeforeTheSettleCancelsIt() {
        val stopped = onTransition(onTransition(State(), Motion.IN_VEHICLE, now), Motion.STILL, now + minute)
        // Traffic lights: the vehicle again two minutes later.
        val again = onTransition(stopped, Motion.IN_VEHICLE, now + 3 * minute)
        assertFalse(shouldSettle(again, now + 3 * minute + SETTLE_MS))
    }

    @Test
    fun stillWithoutAMotionBeforeChangesNothing() {
        val state = onTransition(State(), Motion.STILL, now)
        assertFalse(state.frequent)
        assertFalse(shouldSettle(state, now + 60 * minute))
    }

    @Test
    fun anUnknownActivityChangesNothing() {
        val driving = onTransition(State(), Motion.IN_VEHICLE, now)
        assertEquals(driving, onTransition(driving, "tilting", now + minute))
    }
}
