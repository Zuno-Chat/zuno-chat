package im.zuno.chat

import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.Executors

data class PushDelivery(
    val receivedAtMs: Long,
    val sentAtMs: Long?,
    val originalPriority: String?,
    val deliveredPriority: String?,
    val deviceIdle: Boolean,
    val standbyBucket: Int?,
    val receiverMs: Long? = null,
    val noticePosted: Boolean? = null,
    val serviceStartMs: Long? = null,
    val handling: FcmPushHandling? = null,
    val ackMs: Long? = null,
)

data class PendingDelivery(val delivery: PushDelivery, val receivedAtElapsedMs: Long)

data class PushServiceTiming(
    val startedAtElapsedMs: Long,
    val handling: FcmPushHandling,
    val ackedAtElapsedMs: Long?,
)

class PendingDeliveries(private val capacity: Int) {
    private val entries = object : LinkedHashMap<String, PendingDelivery>() {
        override fun removeEldestEntry(
            eldest: MutableMap.MutableEntry<String, PendingDelivery>?,
        ): Boolean = size > capacity
    }

    fun put(messageId: String, pending: PendingDelivery) {
        entries[messageId] = pending
    }

    fun take(messageId: String): PendingDelivery? = entries.remove(messageId)
}

object PushDeliveryLog {
    private const val PREFERENCES = "FlutterSharedPreferences"
    private const val KEY = "flutter.push.recent_deliveries"
    private const val MAX_ENTRIES = 50
    private const val MAX_PENDING = 32
    private const val TAG = "PushDeliveryLog"
    private val writer = Executors.newSingleThreadExecutor()
    private val pending = PendingDeliveries(MAX_PENDING)

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
        delivery.receiverMs ?: "",
        delivery.noticePosted?.let { if (it) 1 else 0 } ?: "",
        delivery.serviceStartMs ?: "",
        delivery.handling?.wire ?: "",
        delivery.ackMs ?: "",
    ).joinToString("\t")

    fun prepend(existing: String?, line: String, max: Int = MAX_ENTRIES): String {
        val older = existing?.lineSequence()?.filter { it.isNotBlank() } ?: emptySequence()
        return (sequenceOf(line) + older).take(max).joinToString("\n")
    }

    fun replace(existing: String?, old: String, new: String): String? {
        val lines = existing?.lines() ?: return null
        val at = lines.indexOf(old)
        if (at < 0) return null
        return lines.toMutableList().apply { set(at, new) }.joinToString("\n")
    }

    fun completed(pending: PendingDelivery, timing: PushServiceTiming): PushDelivery {
        val since = pending.receivedAtElapsedMs
        return pending.delivery.copy(
            serviceStartMs = (timing.startedAtElapsedMs - since).coerceAtLeast(0),
            handling = timing.handling,
            ackMs = timing.ackedAtElapsedMs?.let { (it - since).coerceAtLeast(0) },
        )
    }

    fun received(
        context: Context,
        messageId: String?,
        extras: Bundle?,
        receivedAtMs: Long,
        receivedAtElapsedMs: Long,
        noticePosted: Boolean?,
    ) {
        val receiverMs = SystemClock.elapsedRealtime() - receivedAtElapsedMs

        @Suppress("DEPRECATION")
        val sentAtMs = sentAtFrom(extras?.get("google.sent_time"))
        val originalPriority = extras?.getString("google.original_priority")
        val deliveredPriority = extras?.getString("google.delivered_priority")
        writer.execute {
            try {
                val delivery = PushDelivery(
                    receivedAtMs = receivedAtMs,
                    sentAtMs = sentAtMs,
                    originalPriority = originalPriority,
                    deliveredPriority = deliveredPriority,
                    deviceIdle = deviceIdle(context),
                    standbyBucket = standbyBucket(context),
                    receiverMs = receiverMs,
                    noticePosted = noticePosted,
                )
                messageId?.let { pending.put(it, PendingDelivery(delivery, receivedAtElapsedMs)) }
                val line = lineFor(delivery)
                Log.i(TAG, line)
                val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                prefs.edit().putString(KEY, prepend(prefs.getString(KEY, null), line)).apply()
            } catch (e: Exception) {
                Log.w(TAG, "Could not record the push delivery", e)
            }
        }
    }

    fun handled(context: Context, messageId: String?, timing: PushServiceTiming) {
        if (messageId == null) return
        writer.execute {
            try {
                val entry = pending.take(messageId) ?: return@execute
                val line = lineFor(completed(entry, timing))
                Log.i(TAG, line)
                val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                replace(prefs.getString(KEY, null), lineFor(entry.delivery), line)?.let {
                    prefs.edit().putString(KEY, it).apply()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not record how the push was handled", e)
            }
        }
    }

    private fun deviceIdle(context: Context): Boolean =
        (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isDeviceIdleMode

    private fun standbyBucket(context: Context): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        return (
            context.getSystemService(
                Context.USAGE_STATS_SERVICE,
            ) as? UsageStatsManager
            )?.appStandbyBucket
    }
}
