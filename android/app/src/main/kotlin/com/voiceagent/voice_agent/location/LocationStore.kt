package com.voiceagent.voice_agent.location

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

/** One row of the stream, as sent to personal-agent. */
data class LogEntry(val id: String, val json: JSONObject)

/**
 * The phone's location queue (ADR-PLATFORM-009): its own database file, apart
 * from the transcripts, so a location failure can never touch the sync queue.
 * A row is written before any send and deleted once personal-agent has
 * answered for it, so this table holds only what has not arrived yet.
 */
class LocationStore private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "location_log.db", null, 1) {

    override fun onConfigure(db: SQLiteDatabase) {
        db.enableWriteAheadLogging()
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE location_queue (
                seq INTEGER PRIMARY KEY AUTOINCREMENT,
                id TEXT NOT NULL UNIQUE,
                payload TEXT NOT NULL
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    /**
     * Returns the row's id: UUIDv7, so a report's row id is its event id, and
     * a later report can name it in `caused_by` (04, §7). An id made ahead can
     * be passed, when it must be known before the row is written.
     */
    fun enqueue(payload: JSONObject, id: String = Uuid7.next()): String {
        payload.put("id", id)
        val values = ContentValues().apply {
            put("id", id)
            put("payload", payload.toString())
        }
        writableDatabase.insertOrThrow("location_queue", null, values)
        return id
    }

    fun oldest(limit: Int): List<LogEntry> {
        val out = ArrayList<LogEntry>()
        readableDatabase.query(
            "location_queue", arrayOf("id", "payload"), null, null, null, null, "seq", limit.toString(),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                out.add(LogEntry(cursor.getString(0), JSONObject(cursor.getString(1))))
            }
        }
        return out
    }

    fun delete(ids: List<String>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            for (id in ids) db.delete("location_queue", "id = ?", arrayOf(id))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun count(): Long =
        readableDatabase.compileStatement("SELECT COUNT(*) FROM location_queue").use { it.simpleQueryForLong() }

    companion object {
        @Volatile private var instance: LocationStore? = null

        fun get(context: Context): LocationStore =
            instance ?: synchronized(this) {
                instance ?: LocationStore(context).also { instance = it }
            }
    }
}
