package im.zuno.chat

import android.content.Context
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

class PushHolds(private val timeoutMs: Long, private val writeOffMs: Long) {
    private class Hold(val key: String?, val at: Long)

    private val holds = ArrayList<Hold>()

    fun acquire(key: String?, now: Long) {
        writeOff(now)
        holds += Hold(eventKey(key), now)
    }

    fun release(key: String?, now: Long): Boolean {
        writeOff(now)
        val eventKey = eventKey(key)
        val index = holds.indexOfFirst { it.key == eventKey }
        if (index < 0) return false
        holds.removeAt(index)
        return holds.none { now - it.at < timeoutMs }
    }

    private fun eventKey(key: String?): String? = key?.ifEmpty { null }

    private fun writeOff(now: Long) {
        holds.removeAll { now - it.at >= writeOffMs }
    }
}

object PushWakeLock {
    private const val TAG = "PushWakeLock"
    private const val WAKE_LOCK_TAG = "zuno:push"
    private const val TIMEOUT_MS = 30_000L
    private const val WRITE_OFF_MS = 300_000L

    private var wakeLock: PowerManager.WakeLock? = null
    private val holds = PushHolds(TIMEOUT_MS, WRITE_OFF_MS)

    @Synchronized
    fun hold(context: Context, key: String?) {
        holds.acquire(key, SystemClock.elapsedRealtime())
        extend(context)
    }

    @Synchronized
    fun extend(context: Context) {
        try {
            lock(context).acquire(TIMEOUT_MS)
        } catch (e: Exception) {
            Log.w(TAG, "Could not take the push wake lock", e)
        }
    }

    @Synchronized
    fun release(key: String?) {
        if (!holds.release(key, SystemClock.elapsedRealtime())) return
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Could not release the push wake lock", e)
        }
    }

    private fun lock(context: Context): PowerManager.WakeLock = wakeLock
        ?: (context.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            .apply { setReferenceCounted(false) }
            .also { wakeLock = it }
}
