package im.zuno.chat.zuno_notifications

import android.content.Context
import android.os.PowerManager
import android.util.Log

object PushWakeLockCount {
    fun afterAcquire(holders: Int, held: Boolean): Int = if (held) holders + 1 else 1

    fun afterRelease(holders: Int): Int = (holders - 1).coerceAtLeast(0)
}

object PushWakeLock {
    private const val TAG = "PushWakeLock"
    private const val WAKE_LOCK_TAG = "zuno:fcm_push"
    private const val TIMEOUT_MS = 30_000L

    private var wakeLock: PowerManager.WakeLock? = null
    private var holders = 0

    @Synchronized
    fun acquire(context: Context) {
        try {
            val lock = wakeLock ?: (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
                .apply { setReferenceCounted(false) }
                .also { wakeLock = it }
            holders = PushWakeLockCount.afterAcquire(holders, lock.isHeld)
            lock.acquire(TIMEOUT_MS)
        } catch (e: Exception) {
            Log.w(TAG, "Could not take the push wake lock", e)
        }
    }

    @Synchronized
    fun release() {
        holders = PushWakeLockCount.afterRelease(holders)
        if (holders > 0) return
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Could not release the push wake lock", e)
        }
    }
}
