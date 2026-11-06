package com.voiceagent.voice_agent.location

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Visits and `once: per_visit` (04, section 5; ADR-NOTIF-003). */
class VisitsTest {
    private val id = "arrival-list:7"
    private val t0 = 1_762_400_000_000L
    private val maxVisitS = 21_600

    private fun trigger(dwellS: Int = 60, version: String = "v1", expiresAtMs: Long = t0 + 3 * 86_400_000L) =
        Trigger(id, version, "place:7", 52.2297, 21.0122, 150, dwellS, "Castorama: 3 rzeczy", expiresAtMs, "przewód")

    private fun step(
        visits: Map<String, Visit>,
        transition: String,
        atMs: Long,
        trigger: Trigger? = trigger(),
    ) = Visits.step(visits, id, trigger, transition, atMs, maxVisitS)

    @Test
    fun enterThenDwellFiresOnceAndExitEndsTheVisit() {
        val entered = step(emptyMap(), "enter", t0)
        assertFalse(entered.fire)
        assertEquals(Visit(t0, fired = false), entered.visits[id])

        val dwelt = step(entered.visits, "dwell", t0 + 60_000)
        assertTrue(dwelt.fire)
        assertEquals(Visit(t0, fired = true), dwelt.visits[id])

        val left = step(dwelt.visits, "exit", t0 + 600_000)
        assertFalse(left.fire)
        assertNull(left.visits[id])
        assertNull(left.endedAtMs)
    }

    @Test
    fun aSecondDwellInOneVisitDoesNotFire() {
        val fired = step(step(emptyMap(), "enter", t0).visits, "dwell", t0 + 60_000)
        val again = step(fired.visits, "dwell", t0 + 120_000)
        assertFalse(again.fire)
        val reentered = step(again.visits, "enter", t0 + 180_000)
        assertFalse(reentered.fire)
    }

    @Test
    fun aDwellWhoseEnterNeverCameBeginsTheVisitAndFires() {
        val dwelt = step(emptyMap(), "dwell", t0)
        assertTrue(dwelt.fire)
        assertEquals(Visit(t0, fired = true), dwelt.visits[id])
    }

    @Test
    fun dwellZeroFiresOnTheEnterAndNotOnTheDwell() {
        val entered = step(emptyMap(), "enter", t0, trigger(dwellS = 0))
        assertTrue(entered.fire)
        val dwelt = step(entered.visits, "dwell", t0 + 1_000, trigger(dwellS = 0))
        assertFalse(dwelt.fire)
    }

    @Test
    fun aVisitAfterAnExitFiresAgain() {
        val first = step(step(emptyMap(), "dwell", t0).visits, "exit", t0 + 600_000)
        val second = step(first.visits, "dwell", t0 + 3_600_000)
        assertTrue(second.fire)
    }

    @Test
    fun anExpiredTriggerBeginsAVisitButNeverFires() {
        val expired = trigger(expiresAtMs = t0)
        val dwelt = step(emptyMap(), "dwell", t0, expired)
        assertFalse(dwelt.fire)
        assertEquals(Visit(t0, fired = false), dwelt.visits[id])
    }

    @Test
    fun aVisitWithNoExitEndsAfterMaxVisit() {
        val fired = step(emptyMap(), "dwell", t0)
        // Just short of six hours: still the same visit.
        val inside = step(fired.visits, "dwell", t0 + maxVisitS * 1000L - 1)
        assertFalse(inside.fire)
        assertNull(inside.endedAtMs)
        // Six hours on, with no exit: that visit ended, a new one begins and fires.
        val later = step(fired.visits, "dwell", t0 + maxVisitS * 1000L + 5_000)
        assertEquals(t0 + maxVisitS * 1000L, later.endedAtMs)
        assertTrue(later.fire)
        assertEquals(Visit(t0 + maxVisitS * 1000L + 5_000, fired = true), later.visits[id])
    }

    @Test
    fun anEnterAfterMaxVisitBeginsANewVisitThatFiresOnItsDwell() {
        val fired = step(emptyMap(), "dwell", t0)
        val entered = step(fired.visits, "enter", t0 + 7 * 3_600_000L)
        assertEquals(t0 + maxVisitS * 1000L, entered.endedAtMs)
        assertFalse(entered.fire)
        assertTrue(step(entered.visits, "dwell", t0 + 7 * 3_600_000L + 60_000).fire)
    }

    @Test
    fun anExitOfAnOldVisitWritesNoMaxVisitEnd() {
        val fired = step(emptyMap(), "dwell", t0)
        val left = step(fired.visits, "exit", t0 + 7 * 3_600_000L)
        assertNull(left.endedAtMs)
        assertNull(left.visits[id])
    }

    @Test
    fun aNewVersionMidVisitDoesNotFireAgain() {
        val fired = step(step(emptyMap(), "enter", t0).visits, "dwell", t0 + 60_000)
        val newList = step(fired.visits, "dwell", t0 + 120_000, trigger(version = "v2"))
        assertFalse(newList.fire)
    }

    @Test
    fun anUnknownIdDropsItsVisitAndNeverFires() {
        val fired = step(emptyMap(), "dwell", t0)
        val unknown = step(fired.visits, "dwell", t0 + 60_000, trigger = null)
        assertFalse(unknown.fire)
        assertNull(unknown.visits[id])
        assertNull(unknown.endedAtMs)
    }

    @Test
    fun otherTriggersVisitsAreLeftAlone() {
        val other = mapOf("arrival-list:9" to Visit(t0 - 1_000, fired = true))
        val dwelt = step(other, "dwell", t0)
        assertEquals(Visit(t0 - 1_000, fired = true), dwelt.visits["arrival-list:9"])
        assertEquals(other, step(dwelt.visits, "exit", t0 + 1_000).visits)
    }

    @Test
    fun withdrawnTriggersArePruned() {
        val visits = mapOf(id to Visit(t0, true), "arrival-list:9" to Visit(t0, false))
        assertEquals(mapOf(id to Visit(t0, true)), Visits.prune(visits, setOf(id, "arrival-list:3")))
        assertEquals(emptyMap<String, Visit>(), Visits.prune(visits, emptySet()))
    }

    @Test
    fun theStateSurvivesAReloadFromItsJson() {
        val fired = step(emptyMap(), "dwell", t0)
        val reloaded = Visits.fromJson(Visits.toJson(fired.visits))
        assertEquals(fired.visits, reloaded)
        // After a restart mid-visit the dwell is not fired again.
        assertFalse(step(reloaded, "dwell", t0 + 60_000).fire)
    }

    @Test
    fun unreadableStateCountsAsNoVisit() {
        assertEquals(emptyMap<String, Visit>(), Visits.fromJson(null))
        assertEquals(emptyMap<String, Visit>(), Visits.fromJson(""))
        assertEquals(emptyMap<String, Visit>(), Visits.fromJson("not json"))
        val partly = Visits.fromJson("""{"a":{"started_at_ms":5,"fired":true},"b":{"fired":"yes"},"c":3}""")
        assertEquals(mapOf("a" to Visit(5, true)), partly)
    }

    @Test
    fun aTapCountsOnceAndOnlyForTheAlertLastShown() {
        val last = mapOf(id to "shown-2", "arrival-list:9" to "shown-9")
        val taken = Visits.takeShown(last, id, "shown-2")
        assertEquals(mapOf("arrival-list:9" to "shown-9"), taken)
        // The same tap again, an older alert of that trigger, a forged id.
        assertNull(Visits.takeShown(taken!!, id, "shown-2"))
        assertNull(Visits.takeShown(last, id, "shown-1"))
        assertNull(Visits.takeShown(last, "arrival-list:404", "shown-2"))
    }

    @Test
    fun notificationIdsStayInTheirRange() {
        for (n in 0 until 500) {
            val nid = ArrivalNotifier.idOf("arrival-list:$n")
            assertTrue(nid in 1_000_000..1_999_999)
        }
        assertEquals(ArrivalNotifier.idOf(id), ArrivalNotifier.idOf(id))
    }
}
