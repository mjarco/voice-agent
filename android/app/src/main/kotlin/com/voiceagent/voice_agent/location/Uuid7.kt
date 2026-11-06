package com.voiceagent.voice_agent.location

import java.security.SecureRandom

/**
 * UUIDv7 (RFC 9562): 48 bits of Unix milliseconds, then a 12-bit counter, then
 * random bits. The row id of every new log row. Within one process the ids
 * rise strictly (RFC 9562, section 6.2, method 1), so a report made in the same
 * millisecond as its cause still sorts after it (04, §7).
 */
object Uuid7 {
    private val random = SecureRandom()
    private var lastMs = -1L
    private var counter = 0

    /** A new millisecond starts the counter low, leaving room to count up. */
    private const val COUNTER_START_MAX = 0x7FF
    private const val COUNTER_MAX = 0xFFF

    @Synchronized
    fun next(nowMs: Long = System.currentTimeMillis()): String {
        if (nowMs > lastMs) {
            lastMs = nowMs
            counter = random.nextInt(COUNTER_START_MAX + 1)
        } else if (counter < COUNTER_MAX) {
            // The same millisecond, or the clock went back: count on from the last.
            counter++
        } else {
            // The counter ran out: borrow the next millisecond.
            lastMs++
            counter = random.nextInt(COUNTER_START_MAX + 1)
        }
        val bytes = ByteArray(16)
        random.nextBytes(bytes)
        for (i in 0 until 6) {
            bytes[i] = (lastMs ushr (8 * (5 - i))).toByte()
        }
        bytes[6] = (0x70 or (counter ushr 8)).toByte() // version 7, counter's high nibble
        bytes[7] = (counter and 0xFF).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte() // variant 10
        val hex = bytes.joinToString("") { "%02x".format(it.toInt() and 0xFF) }
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-" +
            "${hex.substring(16, 20)}-${hex.substring(20)}"
    }
}
