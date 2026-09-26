package im.zuno.chat

import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import java.util.concurrent.Executors

data class PushDelivery(
    val receivedAtMs: Long,
    val sentAtMs: Long?,
    val originalPriority: String?,
    val deliveredPriority: String?,
    val deviceIdle: Boolean,
    val standbyBucket: Int?,
)

object PushDeliveryLog {
    private const val PREFERENCES = "FlutterSharedPreferences"
    private const val KEY = "flutter.push.recent_deliveries"
    private const val MAX_ENTRIES = 50
    private const val TAG = "PushDeliveryLog"
    private val writer = Executors.newSingleThreadExecutor()

    fun sentAtFrom(value: Any?): Long? = when (value) {
        is Long -> value
        is String -> value.toLongOrNull()
        else -> null
    }

    fun lineFor(delivery: PushDelivery): String = listOf(
        delivery.receivedAtMs,
        delivery.sentAtMs ?: "",
        delivery.originalPriority ?: "",
        delivery.deliveredPriority ?: "",
        if (delivery.deviceIdle) 1 else 0,
        delivery.standbyBucket ?: "",
    ).joinToString("\t")

    fun prepend(existing: String?, line: String, max: Int = MAX_ENTRIES): String {
        val older = existing?.lineSequence()?.filter { it.isNotBlank() } ?: emptySequence()
        return (sequenceOf(line) + older).take(max).joinToString("\n")
    }

    fun record(context: Context, extras: Bundle?) {
        val receivedAtMs = System.currentTimeMillis()
        @Suppress("DEPRECATION")
        val sentAtMs = sentAtFrom(extras?.get("google.sent_time"))
        val originalPriority = extras?.getString("google.original_priority")
        val deliveredPriority = extras?.getString("google.delivered_priority")
        writer.execute {
            try {
                val line = lineFor(
                    PushDelivery(
                        receivedAtMs = receivedAtMs,
                        sentAtMs = sentAtMs,
                        originalPriority = originalPriority,
                        deliveredPriority = deliveredPriority,
                        deviceIdle = (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isDeviceIdleMode,
                        standbyBucket = standbyBucket(context),
                    ),
                )
                Log.i(TAG, line)
                val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                prefs.edit().putString(KEY, prepend(prefs.getString(KEY, null), line)).commit()
            } catch (e: Exception) {
                Log.w(TAG, "Could not record the push delivery", e)
            }
        }
    }

    private fun standbyBucket(context: Context): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        return (context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager)?.appStandbyBucket
    }
}
