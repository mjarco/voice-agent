package com.voiceagent.voice_agent.location

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The wake of the glasses names personal-agent's Zakupy view for the place's store types. */
class GlassesWakeTest {
    @Test
    fun aShoppingRouteNamesItsStoreTypes() {
        assertEquals("store_type=fuel", GlassesWake.paramsOf("/shopping?store=fuel"))
        assertEquals("store_type=fuel,grocery", GlassesWake.paramsOf("/shopping?store=fuel,grocery"))
        assertEquals("store_type=diy", GlassesWake.paramsOf("/shopping?store=diy&x=1"))
    }

    @Test
    fun anythingElseWakesNothing() {
        assertNull(GlassesWake.paramsOf(""))
        assertNull(GlassesWake.paramsOf("/agenda"))
        assertNull(GlassesWake.paramsOf("/shopping?store="))
        assertNull(GlassesWake.paramsOf("/shopping?store=Fuel%20x"))
    }

    /** G4: the wake as a document, the trigger's card leading to the store's checklist. */
    @Test
    fun theWakeIsADocument() {
        val t = Trigger("arrival-list:p1", "v1", "p1", 0.0, 0.0, 100, 60, "Biedronka: 2 rzeczy", 0L, "mleko, chleb", "/shopping?store=grocery")
        val d = GlassesWake.docOf(t)!!
        assertEquals(2, d.getInt("version"))
        assertEquals("va:arrival:arrival-list:p1", d.getJSONObject("card").getString("id"))
        assertEquals("Biedronka: 2 rzeczy", d.getJSONObject("card").getString("title"))
        assertEquals("mleko, chleb", d.getJSONObject("card").getString("body"))
        assertEquals("zakupy/grocery", d.getString("open"))
        assertEquals("zakupy", GlassesWake.docOf(t.copy(open = "/shopping?store=fuel,grocery"))!!.getString("open"))
        assertNull(GlassesWake.docOf(t.copy(open = "/agenda")))
    }
}
