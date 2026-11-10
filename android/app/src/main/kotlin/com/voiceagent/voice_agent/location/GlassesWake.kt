package com.voiceagent.voice_agent.location

import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * The arrival also wakes the G2 glasses through glass-native (voice-agent#394; cut C of the
 * workspace's glass-native discussion). The wake names personal-agent's view and its parameters,
 * not a text: glass-native pulls `GET /api/v1/glasses/wakes/zakupy?store_type=…` and shows the
 * notification personal-agent composes; a pick of Zakupy soon after opens that store type.
 *
 * Only a shopping trigger wakes the glasses. Without glass-native installed the broadcast reaches
 * no one, without an error.
 */
object GlassesWake {
    const val PACKAGE = "casa.jarco.glassnative"
    const val ACTION = "casa.jarco.glassnative.action.SHOW"
    private const val SHOPPING = "/shopping?store="

    /** A trigger's route → the view's parameters: "/shopping?store=fuel,grocery" → "store_type=fuel,grocery". */
    fun paramsOf(open: String): String? {
        if (!open.startsWith(SHOPPING)) return null
        val types = open.removePrefix(SHOPPING).substringBefore('&').split(',')
            .map { it.trim() }.filter { it.matches(Regex("[a-z0-9_-]+")) }
        return if (types.isEmpty()) null else "store_type=" + types.joinToString(",")
    }

    /** Sends the wake for [trigger]; false when the trigger is not a shopping one or sending failed. */
    fun send(context: Context, trigger: Trigger): Boolean {
        val params = paramsOf(trigger.open) ?: return false
        return try {
            context.sendBroadcast(
                Intent(ACTION)
                    .setPackage(PACKAGE)
                    .putExtra("view", "zakupy")
                    .putExtra("params", params)
                    .putExtra("id", trigger.id)
                    .putExtra("source", "voice-agent"),
            )
            true
        } catch (failure: Exception) {
            Log.w("GlassesWake", "wake not sent: $failure")
            false
        }
    }
}
