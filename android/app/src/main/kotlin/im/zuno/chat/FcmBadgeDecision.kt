package im.zuno.chat

import im.zuno.chat.zuno_notifications.PushNoticeDecision

enum class FcmPushHandling(val wire: String) {
    DART("dart"),
    CLEAR_MESSAGES("clear"),
    NOTHING("none"),
}

data class ShownNotification(val id: Int, val channelId: String?)

object FcmBadgeDecision {
    const val THREADS_KEY = "flutter.notifications.threads"
    private val messageChannels = setOf("direct_messages", "group_messages", "quiet_messages")

    fun isEventPush(eventId: String?, roomId: String?): Boolean =
        !eventId.isNullOrEmpty() && !roomId.isNullOrEmpty()

    fun handlingFor(data: Map<String, String?>, appInFront: Boolean): FcmPushHandling = when {
        PushNoticeDecision.isTestPush(data["event_id"]) -> FcmPushHandling.NOTHING
        isEventPush(data["event_id"], data["room_id"]) -> FcmPushHandling.DART
        appInFront -> FcmPushHandling.NOTHING
        data["unread"]?.trim()?.toLongOrNull() == 0L -> FcmPushHandling.CLEAR_MESSAGES
        else -> FcmPushHandling.NOTHING
    }

    fun messageNotificationIds(shown: List<ShownNotification>): List<Int> =
        shown.filter { it.channelId in messageChannels }.map { it.id }
}
