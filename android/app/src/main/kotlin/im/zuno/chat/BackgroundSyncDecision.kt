package im.zuno.chat

import android.content.pm.ServiceInfo
import android.os.Build

object BackgroundSyncDecision {
    fun foregroundServiceType(sdkInt: Int): Int =
        if (sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
}
