package com.voiceagent.voice_agent.location

import java.time.OffsetDateTime
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The phone's side of the trigger contract (04), as goal 2 builds it. */
class TriggersTest {
    /** 04, section 3, with what personal-agent sends today (ADR-API-114). */
    private fun trigger(
        id: String = "arrival-list:7",
        version: String = "9c1e4a2b3c4d",
        tweak: JSONObject.() -> Unit = {},
    ): JSONObject = JSONObject(
        """
        {
          "id": "$id",
          "kind": "arrival-list",
          "version": "$version",
          "expires_at": "2026-11-08T00:00:00+01:00",
          "when": {"enter": {"place": "place:7", "lat": 52.2297, "lon": 21.0122, "radius_m": 150, "dwell_s": 60}},
          "guards": {},
          "show": {
            "title": "Castorama: 3 rzeczy",
            "body": "przewód 3-żyłowy, peszel 10 m, …",
            "open": "/shopping?store=diy,garden",
            "surfaces": ["phone"]
          },
          "once": "per_visit"
        }
        """,
    ).apply(tweak)

    private fun set(vararg triggers: JSONObject, contract: Any = 1): JSONObject = JSONObject()
        .put("contract", contract)
        .put("compiled_at", "2026-11-05T10:12:03+01:00")
        .put("detectors", JSONObject().put("max_visit_s", 21600))
        .put("triggers", org.json.JSONArray(triggers.toList()))

    private fun rejectedWhy(raw: JSONObject): String {
        val read = Triggers.parse(set(raw))
        assertEquals(0, read.triggers.size)
        assertEquals(1, read.rejected.size)
        return read.rejected[0].why
    }

    @Test
    fun readsTheContractsExample() {
        val read = Triggers.parseEnvelope(JSONObject().put("data", set(trigger())).toString())
        assertEquals(1, read.triggers.size)
        assertEquals(0, read.rejected.size)
        assertEquals(21600, read.maxVisitS)
        val t = read.triggers[0]
        assertEquals("arrival-list:7", t.id)
        assertEquals("9c1e4a2b3c4d", t.version)
        assertEquals("place:7", t.place)
        assertEquals(52.2297, t.latitude, 0.0)
        assertEquals(21.0122, t.longitude, 0.0)
        assertEquals(150, t.radiusM)
        assertEquals(60, t.dwellS)
        assertEquals("Castorama: 3 rzeczy", t.title)
        assertEquals("przewód 3-żyłowy, peszel 10 m, …", t.body)
        assertEquals(OffsetDateTime.parse("2026-11-08T00:00:00+01:00").toInstant().toEpochMilli(), t.expiresAtMs)
    }

    @Test
    fun aMissingBodyShowsTheTitleAlone() {
        for (body in listOf<Any>(JSONObject.NULL, "", 7)) {
            val read = Triggers.parse(set(trigger { getJSONObject("show").put("body", body) }))
            assertEquals("", read.triggers.single().body)
        }
        val read = Triggers.parse(set(trigger { getJSONObject("show").remove("body") }))
        assertEquals("", read.triggers.single().body)
    }

    @Test
    fun anotherContractIsRefusedAsAWhole() {
        for (contract in listOf<Any>(2, "1", 1.5)) {
            try {
                Triggers.parse(set(trigger(), contract = contract))
                fail("contract $contract was taken")
            } catch (_: TriggerSetException) {
                // The old set stays.
            }
        }
    }

    @Test
    fun aBodyThatIsNotTheSetIsRefused() {
        for (body in listOf("<html>", "{}", """{"data":{"contract":1}}""")) {
            try {
                Triggers.parseEnvelope(body)
                fail("$body was taken")
            } catch (_: TriggerSetException) {
                // The old set stays.
            }
        }
    }

    @Test
    fun whatGoal2DoesNotBuildIsRejectedWithItsReason() {
        assertEquals(
            "condition leave",
            rejectedWhy(trigger { put("when", JSONObject().put("leave", JSONObject())) }),
        )
        assertEquals(
            "conditions at,enter",
            rejectedWhy(trigger { getJSONObject("when").put("at", "2026-11-06T08:00:00+01:00") }),
        )
        assertEquals("guard window", rejectedWhy(trigger { put("guards", JSONObject().put("window", JSONObject())) }))
        assertEquals("once ever", rejectedWhy(trigger { put("once", "ever") }))
        assertEquals(
            "no phone surface",
            rejectedWhy(trigger { getJSONObject("show").put("surfaces", org.json.JSONArray(listOf("glasses"))) }),
        )
    }

    @Test
    fun aMissingFieldIsRejectedNotGuessed() {
        assertEquals("missing dwell_s", rejectedWhy(trigger { getJSONObject("when").getJSONObject("enter").remove("dwell_s") }))
        assertEquals("missing lat", rejectedWhy(trigger { getJSONObject("when").getJSONObject("enter").put("lat", "52") }))
        assertEquals("missing expires_at", rejectedWhy(trigger { put("expires_at", "soon") }))
        assertEquals("missing show.title", rejectedWhy(trigger { getJSONObject("show").remove("title") }))
        assertEquals("missing version", rejectedWhy(trigger { remove("version") }))
    }

    @Test
    fun aNullIsNotAString() {
        assertEquals("missing show.title", rejectedWhy(trigger { getJSONObject("show").put("title", JSONObject.NULL) }))
        assertEquals("missing id", rejectedWhy(trigger { put("id", JSONObject.NULL) }))
        assertEquals("missing place", rejectedWhy(trigger { getJSONObject("when").getJSONObject("enter").put("place", 7) }))
    }

    @Test
    fun noSurfacesIsMissingNotPhone() {
        assertEquals("missing show.surfaces", rejectedWhy(trigger { getJSONObject("show").remove("surfaces") }))
    }

    @Test
    fun whatPlayServicesWouldRefuseIsRejectedAlone() {
        val longId = "arrival-list:" + "x".repeat(100)
        val read = Triggers.parse(set(trigger(), trigger(longId)))
        assertEquals(listOf("arrival-list:7"), read.triggers.map { it.id })
        assertEquals("id too long", read.rejected.single().why)
        assertTrue(read.rejected.single().id.length <= Triggers.MAX_ID_LENGTH)
        assertEquals(
            "dwell_s too long",
            rejectedWhy(trigger { getJSONObject("when").getJSONObject("enter").put("dwell_s", 3_000_000) }),
        )
    }

    @Test
    fun aBodyNestedTooDeepIsRefusedNotFatal() {
        val deep = "[".repeat(200_000) + "]".repeat(200_000)
        try {
            Triggers.parseEnvelope("{\"data\":{\"contract\":1,\"x\":$deep,\"triggers\":[]}}")
        } catch (_: TriggerSetException) {
            // Refused; the old set stays.
        }
    }

    @Test
    fun oneBadTriggerLeavesTheOthers() {
        val read = Triggers.parse(set(trigger(), trigger("arrival-list:8") { put("once", "ever") }))
        assertEquals(listOf("arrival-list:7"), read.triggers.map { it.id })
        assertEquals(listOf("arrival-list:8|9c1e4a2b3c4d"), read.rejected.map { it.key })
    }

    @Test
    fun aRepeatedIdIsRejected() {
        val read = Triggers.parse(set(trigger(), trigger(version = "other")))
        assertEquals(1, read.triggers.size)
        assertEquals("duplicate id", read.rejected.single().why)
    }

    @Test
    fun unknownFieldsAreIgnored() {
        val read = Triggers.parse(
            set(trigger { put("priority", 3); getJSONObject("show").put("icon", "cart") })
                .put("future", JSONObject().put("x", 1)),
        )
        assertEquals(1, read.triggers.size)
        assertEquals(0, read.rejected.size)
    }

    @Test
    fun aMissingNullOrEmptyGuardsIsNoGuard() {
        assertEquals(1, Triggers.parse(set(trigger { remove("guards") })).triggers.size)
        assertEquals(1, Triggers.parse(set(trigger { put("guards", JSONObject.NULL) })).triggers.size)
    }

    @Test
    fun withoutDetectorsAVisitLastsSixHours() {
        val raw = set(trigger()).apply { remove("detectors") }
        assertEquals(21600, Triggers.parse(raw).maxVisitS)
    }

    @Test
    fun theRadiusIsRaisedToAndroidsFloor() {
        val t = Triggers.parse(set(trigger { getJSONObject("when").getJSONObject("enter").put("radius_m", 40) })).triggers[0]
        assertEquals(40, t.radiusM)
        assertEquals(150, Triggers.radiusOf(t))
    }

    @Test
    fun aNewVersionOrTextKeepsTheGeofence() {
        val before = Triggers.parse(set(trigger())).triggers[0]
        val after = Triggers.parse(
            set(trigger(version = "aaaaaaaaaaaa") { getJSONObject("show").put("title", "Castorama: 4 rzeczy") }),
        ).triggers[0]
        assertEquals(Triggers.geofenceKey(before), Triggers.geofenceKey(after))
        val moved = Triggers.parse(set(trigger { getJSONObject("when").getJSONObject("enter").put("lat", 52.3) })).triggers[0]
        assertNotEquals(Triggers.geofenceKey(before), Triggers.geofenceKey(moved))
        val longer = Triggers.parse(set(trigger { getJSONObject("when").getJSONObject("enter").put("dwell_s", 120) })).triggers[0]
        assertNotEquals(Triggers.geofenceKey(before), Triggers.geofenceKey(longer))
    }

    @Test
    fun itWouldFireOnTheDwellUntilItExpires() {
        val t = Triggers.parse(set(trigger())).triggers[0]
        val before = t.expiresAtMs - 1
        assertTrue(Triggers.wouldFire(t, "dwell", before))
        assertFalse(Triggers.wouldFire(t, "enter", before))
        assertFalse(Triggers.wouldFire(t, "dwell", t.expiresAtMs))
        assertTrue(Triggers.expired(t, t.expiresAtMs))
    }

    @Test
    fun withNoDwellItWouldFireOnTheEnter() {
        val t = Triggers.parse(set(trigger { getJSONObject("when").getJSONObject("enter").put("dwell_s", 0) })).triggers[0]
        assertTrue(Triggers.wouldFire(t, "enter", t.expiresAtMs - 1))
        assertFalse(Triggers.wouldFire(t, "dwell", t.expiresAtMs - 1))
    }

    @Test
    fun aRecompiledSetIsNotAChange() {
        val first = set(trigger()).toString()
        val again = set(trigger()).put("compiled_at", "2026-11-05T11:12:03+01:00").toString()
        assertEquals(Triggers.contentOf(first), Triggers.contentOf(again))
        val changed = set(trigger(version = "bbbbbbbbbbbb")).toString()
        assertNotEquals(Triggers.contentOf(first), Triggers.contentOf(changed))
    }

    @Test
    fun theStoredSetReadsBackAlike() {
        val stored = JSONObject(JSONObject().put("data", set(trigger())).toString()).getJSONObject("data").toString()
        assertEquals(Triggers.parse(set(trigger())), Triggers.parse(JSONObject(stored)))
    }
}
