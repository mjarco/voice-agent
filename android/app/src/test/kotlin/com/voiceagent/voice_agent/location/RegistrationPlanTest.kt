package com.voiceagent.voice_agent.location

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** What a registration adds and forgets (ADR-PLATFORM-010 item 3, ADR-PLATFORM-011). */
class RegistrationPlanTest {
    private val t0 = 1_762_400_000_000L
    private val maxVisitS = 21_600

    private fun trigger(id: String, radius: Int = 150) =
        Trigger(id, "v1", "place:$id", 52.2297, 21.0122, radius, 60, "Castorama: 3 rzeczy", t0 + 86_400_000L, "przewód")

    private val a = trigger("arrival-list:1")
    private val b = trigger("arrival-list:2")
    private val held = setOf(a.id, b.id)
    private val heldKeys = setOf(Triggers.geofenceKey(a), Triggers.geofenceKey(b))

    @Test
    fun aRestartAfterAProcessKillWithTheRegistrationStandingAddsNothing() {
        // Defect D2: Android 17 sends the boot broadcast after a plain kill.
        val plan = RegistrationPlan.of(RegistrationPlan.REASON_RESTART_AFTER_STOP, true, listOf(a, b), held, heldKeys)
        assertTrue(plan.intact)
        assertTrue(plan.toAdd.isEmpty())
        assertTrue(plan.gone.isEmpty())
        assertTrue(plan.forget.isEmpty())
    }

    @Test
    fun aRestartAfterAForceStopAddsEverythingAgain() {
        // A force stop cancels the intent, so the registration does not stand.
        val plan = RegistrationPlan.of(RegistrationPlan.REASON_RESTART_AFTER_STOP, false, listOf(a, b), held, heldKeys)
        assertFalse(plan.intact)
        assertEquals(listOf(a, b), plan.toAdd)
    }

    @Test
    fun aRebootAddsEverythingAgainAndForgetsNoVisit() {
        val plan = RegistrationPlan.of("reboot", true, listOf(a, b), held, heldKeys)
        assertFalse(plan.intact)
        assertEquals(listOf(a, b), plan.toAdd)
        assertTrue(plan.forget.isEmpty())
    }

    @Test
    fun aChangedGeofenceIsAddedAndKeepsItsVisit() {
        val moved = trigger(a.id, radius = 300)
        val plan = RegistrationPlan.of(RegistrationPlan.REASON_TRIGGERS, true, listOf(moved, b), held, heldKeys)
        assertEquals(listOf(moved), plan.toAdd)
        assertTrue(plan.forget.isEmpty())
    }

    @Test
    fun aWithdrawnTriggerIsRemovedAndItsVisitForgotten() {
        val plan = RegistrationPlan.of(RegistrationPlan.REASON_TRIGGERS, true, listOf(b), held, heldKeys)
        assertTrue(plan.toAdd.isEmpty())
        assertEquals(setOf(a.id), plan.gone)
        assertEquals(setOf(a.id), plan.forget)
    }

    @Test
    fun aDwellAfterARegistrationMidVisitDoesNotFireAgain() {
        // Defect D1, T17: fired, then a force stop re-adds every geofence, and
        // Play services reports a dwell about 65 s later while you stand inside.
        val entered = Visits.step(emptyMap(), a.id, a, "enter", t0, maxVisitS)
        val fired = Visits.step(entered.visits, a.id, a, "dwell", t0 + 60_000, maxVisitS)
        assertTrue(fired.fire)

        val plan = RegistrationPlan.of(RegistrationPlan.REASON_RESTART_AFTER_STOP, false, listOf(a, b), held, heldKeys)
        val kept = fired.visits - plan.forget
        val again = Visits.step(kept, a.id, a, "dwell", t0 + 300_000, maxVisitS)
        assertFalse(again.fire)
    }

    @Test
    fun aVisitWhoseExitWasMissedEndsAfterMaxVisit() {
        // The cost of keeping visits: an exit lost while the geofence was gone
        // holds the next alert back until max_visit_s, then the visit ends.
        val fired = Visits.step(
            Visits.step(emptyMap(), a.id, a, "enter", t0, maxVisitS).visits,
            a.id, a, "dwell", t0 + 60_000, maxVisitS,
        )
        val back = t0 + maxVisitS * 1000L + 1
        val entered = Visits.step(fired.visits, a.id, a, "enter", back, maxVisitS)
        assertEquals(t0 + maxVisitS * 1000L, entered.endedAtMs)
        val dwelt = Visits.step(entered.visits, a.id, a, "dwell", back + 60_000, maxVisitS)
        assertTrue(dwelt.fire)
    }
}
