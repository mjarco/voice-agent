package com.voiceagent.voice_agent

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class VoiceAgentTileService : TileService() {

    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_ACTIVATION_STATE = "flutter.activation_state"
        private const val KEY_TOGGLE_REQUESTED = "flutter.activation_toggle_requested"
        private const val KEY_FOREGROUND_SERVICE_RUNNING = "flutter.foreground_service_running"
    }

    private fun getPrefs(): SharedPreferences {
        return applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        val prefs = getPrefs()
        val isRunning = prefs.getBoolean(KEY_FOREGROUND_SERVICE_RUNNING, false)

        if (isRunning) {
            // App is alive — signal via SharedPreferences flag
            prefs.edit().putBoolean(KEY_TOGGLE_REQUESTED, true).apply()
        } else {
            // App not alive — launch MainActivity with toggle intent
            val intent = Intent(this, MainActivity::class.java).apply {
                action = MainActivity.ACTION_TOGGLE_ACTIVATION
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(
                        this, 0, intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        }
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val prefs = getPrefs()
        val isActive = prefs.getString(KEY_ACTIVATION_STATE, "idle") == "listening"

        tile.state = if (isActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = if (isActive) "Listening" else "Voice Agent"
        tile.icon = Icon.createWithResource(
            this,
            if (isActive) android.R.drawable.ic_btn_speak_now
            else android.R.drawable.ic_lock_silent_mode_off
        )
        tile.updateTile()
    }
}
