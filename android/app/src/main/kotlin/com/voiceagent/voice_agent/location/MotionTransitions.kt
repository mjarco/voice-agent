package com.voiceagent.voice_agent.location

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity

/**
 * The registration for activity transitions (ADR-PLATFORM-014), taken out in
 * motion mode and removed in every other. Like the location request it is
 * assumed lost after a reboot or an update, so each reconcile renews it.
 */
object MotionTransitions {
    private const val REQUEST_CODE = 4103

    /** The API's activities the log asks for, ENTER only, by the names of [Motion]. */
    private val activities = mapOf(
        DetectedActivity.STILL to Motion.STILL,
        DetectedActivity.WALKING to Motion.WALKING,
        DetectedActivity.RUNNING to Motion.RUNNING,
        DetectedActivity.ON_BICYCLE to Motion.ON_BICYCLE,
        DetectedActivity.IN_VEHICLE to Motion.IN_VEHICLE,
    )

    fun name(activityType: Int): String? = activities[activityType]

    /** Android 10+ asks for it at run time; below, the manifest's Play services permission is enough. */
    fun permissionGranted(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED

    private fun intent(context: Context, flags: Int): PendingIntent? {
        val intent = Intent(context, MotionReceiver::class.java).setAction(MotionReceiver.ACTION)
        // Mutable: Play services fills in the result.
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags or PendingIntent.FLAG_MUTABLE)
    }

    /** Runs on the pipeline's thread; failures arrive later and are written there too. */
    fun subscribe(context: Context, reason: String) {
        if (!permissionGranted(context)) return
        val request = ActivityTransitionRequest(
            activities.keys.map {
                ActivityTransition.Builder()
                    .setActivityType(it)
                    .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                    .build()
            },
        )
        val pending = intent(context, PendingIntent.FLAG_UPDATE_CURRENT)!!
        try {
            ActivityRecognition.getClient(context)
                .requestActivityTransitionUpdates(request, pending)
                .addOnFailureListener { failure ->
                    LocationPipeline.write(context) {
                        LocationPipeline.recordStatus(context, "motion_subscribe_failed", "$reason: ${failure.message}")
                    }
                }
        } catch (failure: SecurityException) {
            LocationPipeline.recordStatus(context, "motion_subscribe_failed", "$reason: permission: ${failure.message}")
        }
    }

    fun unsubscribe(context: Context) {
        val pending = intent(context, PendingIntent.FLAG_NO_CREATE) ?: return
        try {
            ActivityRecognition.getClient(context).removeActivityTransitionUpdates(pending)
        } catch (_: SecurityException) {
            // Without the permission there is nothing registered to remove.
        }
        pending.cancel()
    }
}
