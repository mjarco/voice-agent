package com.voiceagent.voice_agent.location

import com.voiceagent.voice_agent.location.LocationWatch.AFTER_UPDATE_DELAY_SECONDS
import com.voiceagent.voice_agent.location.LocationWatch.RETRY_AFTER_MS
import com.voiceagent.voice_agent.location.LocationWatch.STALE_AFTER_MS
import com.voiceagent.voice_agent.location.LocationWatch.isStale
import com.voiceagent.voice_agent.location.LocationWatch.resubscribesAfterUpdate
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The watch re-subscribes when readings stop, once per stale stretch and retry window (ADR-PLATFORM-012). */
class LocationWatchTest {
    private val minute = 60_000L
    private val now = 1_800_000_000_000L

    @Test
    fun readingsComingInAreNotStale() {
        assertFalse(isStale(now, now - 5 * minute, now - 600 * minute, 0))
        assertFalse(isStale(now, now - STALE_AFTER_MS + 1, 0, 0))
    }

    @Test
    fun noReadingForHalfAnHourIsStale() {
        assertTrue(isStale(now, now - STALE_AFTER_MS, now - 600 * minute, 0))
        // The day after the update to 1.29.0: one subscription, no reading since.
        assertTrue(isStale(now, now - 25 * 60 * minute, now - 25 * 60 * minute, 0))
    }

    @Test
    fun aFreshSubscriptionGetsItsOwnHalfHour() {
        assertFalse(isStale(now, now - 600 * minute, now - 10 * minute, 0))
        assertTrue(isStale(now, now - 600 * minute, now - STALE_AFTER_MS, 0))
    }

    @Test
    fun aStaleStretchIsAnsweredOncePerRetryWindow() {
        val lastReading = now - 300 * minute
        val staleAt = now - 40 * minute
        // Re-subscribed 40 minutes ago, still nothing: wait for the retry window.
        assertFalse(isStale(now, lastReading, staleAt, staleAt))
        assertTrue(isStale(staleAt + RETRY_AFTER_MS, lastReading, staleAt, staleAt))
    }

    @Test
    fun aReadingAfterTheLastStaleStartsANewStretch() {
        val staleAt = now - 90 * minute
        val lastReading = now - 60 * minute
        assertTrue(isStale(now, lastReading, staleAt, staleAt))
    }

    @Test
    fun aLogThatNeverSubscribedIsStale() {
        assertTrue(isStale(now, 0, 0, 0))
    }

    @Test
    fun anUpdateIsFollowedByASecondSubscriptionInBackgroundModeOnly() {
        assertTrue(resubscribesAfterUpdate(enabled = true, mode = LocationConfig.MODE_BACKGROUND))
        assertFalse(resubscribesAfterUpdate(enabled = true, mode = LocationConfig.MODE_FOREGROUND))
        assertFalse(resubscribesAfterUpdate(enabled = false, mode = LocationConfig.MODE_BACKGROUND))
    }

    @Test
    fun theSecondSubscriptionWaitsPastPlayServicesClearingTheUpdate() {
        // Cleared 117 ms after the subscription at the 1.29.1 install
        // (ADR-PLATFORM-013); a minute leaves a wide margin.
        assertTrue(AFTER_UPDATE_DELAY_SECONDS >= 60)
        assertTrue(AFTER_UPDATE_DELAY_SECONDS * 1000 < STALE_AFTER_MS)
    }
}
