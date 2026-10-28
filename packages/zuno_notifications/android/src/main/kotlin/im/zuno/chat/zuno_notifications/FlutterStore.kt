package im.zuno.chat.zuno_notifications

import android.content.Context
import android.content.SharedPreferences

object FlutterStore {
    const val FILE = "FlutterSharedPreferences"
    const val PREFIX = "flutter."
    const val RINGING_CALL = "${PREFIX}calls.ringing_notification"
    const val RESOLVED_CALL_PREFIX = "${PREFIX}calls.resolved."
    const val ROOM_CACHE = "${PREFIX}notifications.rooms"
    const val THREADS = "${PREFIX}notifications.threads"
    const val RECENT_DELIVERIES = "${PREFIX}push.recent_deliveries"
    const val FCM_TOKEN = "${PREFIX}push.fcm.token"
    const val NOTIFICATION_PREVIEW = "${PREFIX}settings.notification_preview"
    const val NOTIFY_ME = "${PREFIX}settings.notify_me"
    const val MESSAGE_TONE = "${PREFIX}settings.message_tone_enabled"
    const val MESSAGE_VIBRATION = "${PREFIX}settings.message_vibration_enabled"
    const val RINGTONE = "${PREFIX}settings.ringtone_enabled"
    const val CALL_VIBRATION = "${PREFIX}settings.call_vibration_enabled"
    const val PREVIEW_HIDDEN = "nothing"
    const val NOTIFY_ME_MENTIONS_ONLY = "mentionsOnly"

    fun preferences(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)
}
