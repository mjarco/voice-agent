package com.voiceagent.voice_agent.location

import java.security.SecureRandom

/**
 * UUIDv7 (RFC 9562): 48 bits of Unix milliseconds, then random bits. The row
 * id of every new log row, so ids sort by when the phone made them (04, §7).
 */
object Uuid7 {
    private val random = SecureRandom()

    fun next(nowMs: Long = System.currentTimeMillis()): String {
        val bytes = ByteArray(16)
        random.nextBytes(bytes)
        for (i in 0 until 6) {
            bytes[i] = (nowMs ushr (8 * (5 - i))).toByte()
        }
        bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x70).toByte() // version 7
        bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte() // variant 10
        val hex = bytes.joinToString("") { "%02x".format(it.toInt() and 0xFF) }
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-" +
            "${hex.substring(16, 20)}-${hex.substring(20)}"
    }
}
