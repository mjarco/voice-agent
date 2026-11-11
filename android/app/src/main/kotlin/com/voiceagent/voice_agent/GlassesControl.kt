package com.voiceagent.voice_agent

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The microphone mode driven from the G2 glasses through glass-native (ADR-AUDIO-016;
 * glass-native's docs/va-control-protocol.md).
 *
 * In: glass-native sends [ACTION_MIC] to this package with `command` = listening | standby | off |
 * status, under the permission `<applicationId>.permission.MIC`. A command goes to Dart through
 * [GlassesControlBridge]; without a running engine it is blocked. An ordered broadcast gets the
 * answer: result data = accepted | blocked | refused | status, extras `mode` (the mode now) and
 * `reason`.
 *
 * Out: every mode Dart reports goes to glass-native as [ACTION_MODE], so its page shows the real mode.
 */
object GlassesControl {
    const val ACTION_MIC = "com.voiceagent.voice_agent.action.MIC"
    const val GLASS_NATIVE = "casa.jarco.glassnative"
    const val ACTION_MODE = "casa.jarco.glassnative.action.VA_MODE"
    private const val TAG = "GlassesControl"

    /** The mode Dart last reported; a process without an engine is Off. */
    @Volatile
    var mode: String = "off"
        private set

    /** Set while an engine listens for commands. */
    var sink: EventChannel.EventSink? = null

    /** Hands [command] to Dart; false when no engine listens. Main thread. */
    fun deliver(command: String): Boolean {
        val s = sink ?: return false
        s.success(command)
        return true
    }

    fun report(context: Context, newMode: String) {
        mode = newMode
        try {
            context.sendBroadcast(
                Intent(ACTION_MODE)
                    .setPackage(GLASS_NATIVE)
                    .putExtra("mode", newMode)
                    .putExtra("source", context.packageName),
            )
        } catch (failure: Exception) {
            // Without glass-native installed the broadcast reaches no one, without an error.
            Log.w(TAG, "mode not sent: $failure")
        }
    }
}

/** The channels of [GlassesControl] for one engine. */
class GlassesControlBridge(context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val appContext = context.applicationContext

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "reportMode" -> {
                val mode = call.argument<String>("mode")
                if (mode == null) return result.error("bad_args", "mode missing", null)
                GlassesControl.report(appContext, mode)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        GlassesControl.sink = events
    }

    override fun onCancel(arguments: Any?) {
        GlassesControl.sink = null
    }

    /** The engine goes away: no session survives it, so the glasses learn Off. */
    fun dispose() {
        GlassesControl.sink = null
        if (GlassesControl.mode != "off") GlassesControl.report(appContext, "off")
    }
}

/** The way in from glass-native; exported under the permission `<applicationId>.permission.MIC`. */
class GlassesControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != GlassesControl.ACTION_MIC) return
        val command = intent.getStringExtra("command")
        val source = intent.getStringExtra("source") ?: "intent"
        val (status, reason) = when (command) {
            "status" -> "status" to null
            "listening", "standby", "off" ->
                if (GlassesControl.deliver(command)) "accepted" to null
                else "blocked" to "voice-agent is not running"
            else -> "refused" to "unknown command: $command"
        }
        Log.i("GlassesControl", "$source: $command → $status ${reason ?: ""} (mode ${GlassesControl.mode})")
        // Only an ordered broadcast carries a result back; for any other the call is a no-op.
        runCatching {
            setResult(
                if (status == "accepted" || status == "status") Activity.RESULT_OK else Activity.RESULT_FIRST_USER,
                status,
                Bundle().apply {
                    putString("mode", GlassesControl.mode)
                    putString("reason", reason)
                },
            )
        }
    }
}
