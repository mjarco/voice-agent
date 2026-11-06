package com.voiceagent.voice_agent.location

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.voiceagent.voice_agent.MainActivity
import java.time.Instant
import java.util.zip.CRC32
import org.json.JSONArray
import org.json.JSONObject

/**
 * Arrival alerts, posted natively (ADR-NOTIF-003): the second writer of
 * notifications beside Dart's `LocalNotificationService` (ADR-NOTIF-001). It
 * writes only its own channel and its own id range, and touches nothing of
 * Flutter's. Runs on the pipeline's thread, from [GeofenceReceiver].
 */
object ArrivalNotifier {
    const val CHANNEL_ID = "arrival_alerts"

    /** Ids 1 000 000–1 999 999: free of Flutter's (ADR-NOTIF-001, rule 5) and of the services'. */
    const val ID_BASE = 1_000_000
    private const val ID_SPAN = 1_000_000

    fun idOf(triggerId: String): Int {
        val crc = CRC32().apply { update(triggerId.toByteArray()) }.value
        return ID_BASE + (crc % ID_SPAN).toInt()
    }

    /**
     * The trigger fired (04, section 7): `trigger.fired`, then `trigger.shown`
     * once the system has taken it. When notifications are off, the fired row
     * says `"shown":false` and why, and the visit's once is spent anyway.
     */
    fun fire(context: Context, trigger: Trigger, enteredId: String, at: Instant) {
        // Made ahead, in order: the swipe's intent must name the shown row.
        val firedId = Uuid7.next()
        val shownId = Uuid7.next()
        // The visit's once is already spent, so a failure here still writes its row.
        val why = try {
            blocked(context) ?: run {
                post(context, trigger, shownId, at)
                null
            }
        } catch (failure: Exception) {
            "post_failed: ${failure.javaClass.simpleName}"
        }
        val fired = JSONObject()
            .put("trigger", trigger.id)
            .put("v", trigger.version)
            .put("surface", "phone")
            .put("caused_by", JSONArray().put(enteredId))
            .put("shown", why == null)
        if (why != null) fired.put("why", why)
        LocationPipeline.recordStatus(context, "trigger.fired", fired, at, firedId)
        if (why != null) return
        LocationPipeline.recordStatus(
            context,
            "trigger.shown",
            JSONObject().put("trigger", trigger.id).put("v", trigger.version).put("caused_by", JSONArray().put(firedId)),
            at,
            shownId,
        )
    }

    /** Why nothing could show now, or null when it can. */
    private fun blocked(context: Context): String? {
        // False with POST_NOTIFICATIONS refused on Android 13+, or the app's notifications off.
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return "notifications_off"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java)
            ensureChannel(manager)
            if (manager.getNotificationChannel(CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE) {
                return "channel_off"
            }
        }
        return null
    }

    /**
     * Made when the switch goes on, so the channel is in the system's settings
     * before the first alert. Heads-up with sound; once made, only you change it.
     */
    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        ensureChannel(context.getSystemService(NotificationManager::class.java))
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Alerty w sklepach", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Lista zakupów, gdy wchodzisz do sklepu"
            },
        )
    }

    @SuppressLint("MissingPermission") // checked in blocked()
    private fun post(context: Context, trigger: Trigger, shownId: String, at: Instant) {
        val id = idOf(trigger.id)
        // The tap opens the app as the launcher does; the trigger's route is task 6.
        val open = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val dismiss = Intent(context, ArrivalDismissReceiver::class.java)
            .setAction(ArrivalDismissReceiver.ACTION)
            .putExtra(ArrivalDismissReceiver.EXTRA_TRIGGER, trigger.id)
            .putExtra(ArrivalDismissReceiver.EXTRA_VERSION, trigger.version)
            .putExtra(ArrivalDismissReceiver.EXTRA_SHOWN, shownId)
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(trigger.title)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            // Android 7 has no channels: the same heads-up with sound.
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setWhen(at.toEpochMilli())
            .setShowWhen(true)
            .setContentIntent(PendingIntent.getActivity(context, id, open, flags))
            // A swipe, not a tap: auto-cancel on a tap sends no delete intent.
            .setDeleteIntent(PendingIntent.getBroadcast(context, id, dismiss, flags))
        if (trigger.body.isNotEmpty()) {
            builder.setContentText(trigger.body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(trigger.body))
        }
        NotificationManagerCompat.from(context).notify(id, builder.build())
    }
}
