package com.voiceagent.voice_agent.location

import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONObject

/**
 * The arrival also wakes the G2 glasses through glass-native (voice-agent#394; cut C of the
 * workspace's glass-native discussion). The wake names personal-agent's view and its parameters,
 * not a text: glass-native pulls `GET /api/v1/glasses/wakes/zakupy?store_type=…` and shows the
 * notification personal-agent composes; a pick of Zakupy soon after opens that store type.
 *
 * Only a shopping trigger wakes the glasses. Without glass-native installed the broadcast reaches
 * no one, without an error.
 *
 * Since G4 (workspace off-roadmap task 2026-11-15-g4-glasses-va-author) voice-agent writes the wake
 * itself as a markup v2 document (`doc`): the trigger's card, and the store's checklist as the
 * screen a pick lands on. `view` and `params` stay beside it for a glass-native before G4.
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

    /** The store's screen a pick lands on: its checklist for one store type, Zakupy for several. */
    fun screenOf(params: String): String {
        val types = params.removePrefix("store_type=").split(',')
        return if (types.size == 1) "zakupy/${types[0]}" else "zakupy"
    }

    /** The wake for [trigger] as a document of glass-native's markup v2, or null when not a shopping one. */
    fun docOf(trigger: Trigger): JSONObject? {
        val params = paramsOf(trigger.open) ?: return null
        return JSONObject()
            .put("version", 2)
            .put("card", JSONObject().put("id", "va:arrival:${trigger.id}").put("title", trigger.title).put("body", trigger.body))
            .put("open", screenOf(params))
    }

    /** Hands glass-native a document written here or in Dart (G4); false when sending failed. */
    fun sendDoc(context: Context, doc: String): Boolean = try {
        context.sendBroadcast(Intent(ACTION).setPackage(PACKAGE).putExtra("doc", doc).putExtra("source", "voice-agent"))
        true
    } catch (failure: Exception) {
        Log.w("GlassesWake", "document not sent: $failure")
        false
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
                    .putExtra("doc", docOf(trigger).toString())
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
