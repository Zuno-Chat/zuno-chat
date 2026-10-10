package im.zuno.chat

import android.content.Context
import android.util.Log

data class CaughtError(
    val label: String,
    val type: String,
    val message: String,
    val stack: String,
) {
    fun toMap(): Map<String, String> = mapOf(
        "kind" to "caught",
        "label" to label,
        "type" to type,
        "message" to message,
        "stack" to stack,
    )
}

object CaughtErrors {
    const val LIMIT = 20
    const val FRAMES = 8
    private const val MESSAGE_LIMIT = 500
    private const val PREFERENCES = "zuno_caught_errors"
    private const val KEY = "pending"
    private const val ENTRY = '\u001E'
    private const val FIELD = '\u001F'
    private const val TAG = "CaughtErrors"

    fun record(context: Context, label: String, error: Throwable) {
        Log.w(TAG, label, error)
        synchronized(this) {
            val prefs = preferences(context)
            val updated = appended(prefs.getString(KEY, null), entryFor(label, error)) ?: return
            prefs.edit().putString(KEY, updated).apply()
        }
    }

    fun take(context: Context): List<CaughtError> = synchronized(this) {
        val prefs = preferences(context)
        val pending = parse(prefs.getString(KEY, null))
        prefs.edit().remove(KEY).apply()
        pending
    }

    fun entryFor(label: String, error: Throwable) = CaughtError(
        label = label,
        type = error.javaClass.name,
        message = error.message.orEmpty().take(MESSAGE_LIMIT),
        stack = error.stackTrace.take(FRAMES).joinToString("\n") { "at $it" },
    )

    fun appended(stored: String?, entry: CaughtError): String? {
        val pending = parse(stored)
        if (pending.any { it.label == entry.label }) return null
        return (pending + entry).takeLast(LIMIT).joinToString(ENTRY.toString()) { encode(it) }
    }

    fun parse(stored: String?): List<CaughtError> {
        if (stored.isNullOrEmpty()) return emptyList()
        return stored.split(ENTRY).mapNotNull { line ->
            val fields = line.split(FIELD)
            if (fields.size != 4) null else CaughtError(fields[0], fields[1], fields[2], fields[3])
        }
    }

    private fun encode(entry: CaughtError) =
        listOf(entry.label, entry.type, entry.message, entry.stack)
            .joinToString(FIELD.toString()) { it.filterNot { char -> char == ENTRY || char == FIELD } }

    private fun preferences(context: Context) =
        context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
}
