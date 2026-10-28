package im.zuno.chat

import android.content.Context
import im.zuno.chat.zuno_notifications.FlutterStore

object FcmPushKeys {
    fun registeredToken(context: Context): String? =
        FlutterStore.preferences(context).getString(FlutterStore.FCM_TOKEN, null)?.ifEmpty { null }

    fun messageId(raw: String?): String? = raw?.takeIf { it.isNotEmpty() }

    fun shouldForwardToken(registered: String?, fresh: String): Boolean =
        !registered.isNullOrEmpty() && registered != fresh
}
