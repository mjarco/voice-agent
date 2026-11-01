package com.voiceagent.voice_agent.location

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * What the native pipeline remembers. It runs without Flutter, so it cannot read
 * flutter_secure_storage; Dart hands it the URL and token, and the token is kept
 * here under an Android Keystore key, in line with ADR-DATA-004.
 */
class LocationConfig(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("location_log", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(value) = prefs.edit().putBoolean("enabled", value).apply()

    var mode: String
        get() = prefs.getString("mode", MODE_BACKGROUND) ?: MODE_BACKGROUND
        set(value) = prefs.edit().putString("mode", value).apply()

    var foregroundIntervalSeconds: Int
        get() = prefs.getInt("foreground_interval_s", DEFAULT_FOREGROUND_INTERVAL_S)
        set(value) = prefs.edit().putInt("foreground_interval_s", value).apply()

    /** The interval asked for in the current mode. */
    val intervalSeconds: Int
        get() = if (mode == MODE_FOREGROUND) foregroundIntervalSeconds else BACKGROUND_INTERVAL_S

    var apiUrl: String?
        get() = prefs.getString("api_url", null)
        set(value) = prefs.edit().putString("api_url", value).apply()

    var token: String?
        get() = prefs.getString("token", null)?.let(::decrypt)
        set(value) = prefs.edit().putString("token", value?.takeIf { it.isNotEmpty() }?.let(::encrypt)).apply()

    var lastReadingAtMs: Long
        get() = prefs.getLong("last_reading_at", 0)
        set(value) = prefs.edit().putLong("last_reading_at", value).apply()

    var lastSentAtMs: Long
        get() = prefs.getLong("last_sent_at", 0)
        set(value) = prefs.edit().putLong("last_sent_at", value).apply()

    var lastError: String?
        get() = prefs.getString("last_error", null)
        set(value) = prefs.edit().putString("last_error", value).apply()

    var lastPermission: String?
        get() = prefs.getString("last_permission", null)
        set(value) = prefs.edit().putString("last_permission", value).apply()

    var lastBatterySaver: Boolean?
        get() = if (prefs.contains("last_battery_saver")) prefs.getBoolean("last_battery_saver", false) else null
        set(value) = prefs.edit().putBoolean("last_battery_saver", value ?: false).apply()

    var lastLocationOn: Boolean?
        get() = if (prefs.contains("last_location_on")) prefs.getBoolean("last_location_on", true) else null
        set(value) = prefs.edit().putBoolean("last_location_on", value ?: true).apply()

    var lastBootCount: Int
        get() = prefs.getInt("last_boot_count", -2)
        set(value) = prefs.edit().putInt("last_boot_count", value).apply()

    var lastExitSeenAtMs: Long
        get() = prefs.getLong("last_exit_seen_at", 0)
        set(value) = prefs.edit().putLong("last_exit_seen_at", value).apply()

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as SecretKey?)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(plain.toByteArray())
        return Base64.encodeToString(sealed, Base64.NO_WRAP)
    }

    private fun decrypt(stored: String): String? = try {
        val sealed = Base64.decode(stored, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, IV_BYTES))
        String(cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES))
    } catch (_: Exception) {
        // A key lost to a restore: the app hands the token over again at start.
        null
    }

    companion object {
        const val MODE_BACKGROUND = "background"
        const val MODE_FOREGROUND = "foreground"
        const val BACKGROUND_INTERVAL_S = 300
        const val DEFAULT_FOREGROUND_INTERVAL_S = 30

        private const val KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "location_log_token"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_BYTES = 12
    }
}
