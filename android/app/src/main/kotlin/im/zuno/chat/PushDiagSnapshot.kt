package im.zuno.chat

import android.app.NotificationManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationManagerCompat

object PushDiagSnapshot {
    private const val TAG = "ZunoPushDiag"

    fun read(context: Context): Map<String, Any> {
        val snapshot = mutableMapOf<String, Any>()
        fun put(key: String, read: () -> Any?) {
            try {
                read()?.let { snapshot[key] = it }
            } catch (e: Exception) {
                Log.w(TAG, "Could not read $key", e)
            }
        }
        val notifications =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        put("notificationsEnabled") {
            NotificationManagerCompat.from(context).areNotificationsEnabled()
        }
        put("channels") { channels(notifications) }
        put("fullScreenIntent") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                notifications.canUseFullScreenIntent()
            } else {
                true
            }
        }
        put("batteryOptimizationIgnored") {
            (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
                .isIgnoringBatteryOptimizations(context.packageName)
        }
        put("backgroundData") {
            val connectivity =
                context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            PushDiagDecision.backgroundDataName(connectivity.restrictBackgroundStatus)
        }
        put("standbyBucket") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                (context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager)
                    ?.appStandbyBucket
            } else {
                null
            }
        }
        return snapshot
    }

    private fun channels(manager: NotificationManager): List<Map<String, Any>>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()
        val blockedGroups = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.notificationChannelGroups.filter { it.isBlocked }.map { it.id }.toSet()
        } else {
            emptySet()
        }
        return manager.notificationChannels.map { channel ->
            mapOf(
                "id" to channel.id,
                "name" to channel.name.toString(),
                "importance" to PushDiagDecision.importanceName(
                    channel.importance,
                    groupBlocked = channel.group in blockedGroups,
                ),
            )
        }
    }
}
