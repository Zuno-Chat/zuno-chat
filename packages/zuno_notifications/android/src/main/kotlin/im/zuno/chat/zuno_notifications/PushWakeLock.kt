package im.zuno.chat.zuno_notifications

import android.content.Context
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

class PushWakeLockKeys(private val timeoutMs: Long) {
    private val held = LinkedHashMap<String, Long>()

    fun acquire(key: String, now: Long) {
        prune(now)
        held[key] = now
    }

    fun release(key: String, now: Long): Boolean {
        prune(now)
        if (held.remove(key) == null) return false
        return held.isEmpty()
    }

    private fun prune(now: Long) {
        held.entries.removeAll { now - it.value >= timeoutMs }
    }
}

object PushWakeLock {
    private const val TAG = "PushWakeLock"
    private const val WAKE_LOCK_TAG = "zuno:fcm_push"
    private const val TIMEOUT_MS = 30_000L

    private var wakeLock: PowerManager.WakeLock? = null
    private val keys = PushWakeLockKeys(TIMEOUT_MS)

    @Synchronized
    fun acquire(context: Context, key: String) {
        try {
            val lock = wakeLock ?: (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
                .apply { setReferenceCounted(false) }
                .also { wakeLock = it }
            keys.acquire(key, SystemClock.elapsedRealtime())
            lock.acquire(TIMEOUT_MS)
        } catch (e: Exception) {
            Log.w(TAG, "Could not take the push wake lock", e)
        }
    }

    @Synchronized
    fun release(key: String) {
        if (!keys.release(key, SystemClock.elapsedRealtime())) return
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Could not release the push wake lock", e)
        }
    }
}
