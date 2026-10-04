package im.zuno.chat

import android.app.NotificationManager
import android.net.ConnectivityManager

object PushDiagDecision {
    fun importanceName(importance: Int, groupBlocked: Boolean): String {
        if (groupBlocked) return "none"
        return when (importance) {
            NotificationManager.IMPORTANCE_NONE -> "none"
            NotificationManager.IMPORTANCE_MIN -> "min"
            NotificationManager.IMPORTANCE_LOW -> "low"
            NotificationManager.IMPORTANCE_DEFAULT -> "default"
            NotificationManager.IMPORTANCE_HIGH -> "high"
            NotificationManager.IMPORTANCE_MAX -> "max"
            else -> "unknown"
        }
    }

    fun backgroundDataName(status: Int): String = when (status) {
        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED -> "allowed"
        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_WHITELISTED -> "exempt"
        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED -> "restricted"
        else -> "unknown"
    }
}
