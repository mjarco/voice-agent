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
}
