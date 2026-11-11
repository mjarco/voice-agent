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
        assertEquals(State(frequent = true, activity = Motion.IN_VEHICLE, atMs = now, intervalS = 10, anchorAtMs = now), state)
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

    @Test
    fun aLateStartAnchorsWhenTheReadingsStart() {
        // The event happened 20 minutes ago; the batch arrives now.
        val state = onTransition(State(), Motion.IN_VEHICLE, now - 20 * minute, now)
        assertEquals(now, state.anchorAtMs)
        assertFalse(shouldSettle(state, now + minute))
    }

    @Test
    fun movingFarEnoughMovesTheAnchor() {
        val driving = onTransition(State(), Motion.IN_VEHICLE, now)
        val first = Motion.onReading(driving, 52.0, 21.0, now + minute)
        assertEquals(now + minute, first.anchorAtMs)
        // About 30 m: the anchor stays.
        val near = Motion.onReading(first, 52.0003, 21.0, now + 2 * minute)
        assertEquals(now + minute, near.anchorAtMs)
        // About 220 m: it moves.
        val far = Motion.onReading(near, 52.002, 21.0, now + 3 * minute)
        assertEquals(now + 3 * minute, far.anchorAtMs)
        assertEquals(52.002, far.anchorLat!!, 1e-9)
    }

    @Test
    fun aMissedStillSettlesWhenThePhoneStopsMoving() {
        val parked = Motion.onReading(onTransition(State(), Motion.IN_VEHICLE, now), 52.0, 21.0, now + minute)
        // Readings keep coming from the same spot; no `still` arrives.
        val later = Motion.onReading(parked, 52.0001, 21.0001, now + 9 * minute)
        assertEquals(null, Motion.settleReason(later, now + minute + Motion.STATIONARY_MS - 1))
        assertEquals(Motion.SETTLED_STATIONARY, Motion.settleReason(later, now + minute + Motion.STATIONARY_MS))
    }

    @Test
    fun noReadingAtAllSettlesToo() {
        val started = onTransition(State(), Motion.IN_VEHICLE, now)
        assertEquals(Motion.SETTLED_STATIONARY, Motion.settleReason(started, now + Motion.STATIONARY_MS))
    }

    @Test
    fun anotherMotionKeepsTheAnchor() {
        val driving = Motion.onReading(onTransition(State(), Motion.IN_VEHICLE, now), 52.0, 21.0, now + minute)
        val walking = onTransition(driving, Motion.WALKING, now + 5 * minute)
        assertEquals(driving.anchorAtMs, walking.anchorAtMs)
    }

    @Test
    fun stillIsTheReasonWhenItComesFirst() {
        val stopped = onTransition(onTransition(State(), Motion.IN_VEHICLE, now), Motion.STILL, now + minute)
        assertEquals(Motion.SETTLED_STILL, Motion.settleReason(stopped, now + minute + SETTLE_MS))
    }

    @Test
    fun readingsInTheBackgroundDoNotMoveTheAnchor() {
        assertEquals(State(), Motion.onReading(State(), 52.0, 21.0, now))
    }

    @Test
    fun theDistanceIsRightForAKnownPair() {
        // 0.001 degree of latitude is about 111 m.
        assertEquals(111.2, Motion.distanceMeters(52.0, 21.0, 52.001, 21.0), 0.5)
    }
}
