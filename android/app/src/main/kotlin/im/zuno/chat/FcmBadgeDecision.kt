package im.zuno.chat

import im.zuno.chat.zuno_notifications.PushKind

enum class FcmPushHandling(val wire: String) {
    DART("dart"),
    RING("ring"),
    CLEAR_MESSAGES("clear"),
    NOTHING("none"),
}

data class ShownNotification(val id: Int, val channelId: String?)

object FcmBadgeDecision {
    private val messageChannels = setOf("direct_messages", "group_messages", "quiet_messages")

    fun handlingFor(data: Map<String, String?>, appInFront: Boolean): FcmPushHandling =
        when (RingBlob.pushKind(data["event_id"], data["room_id"], data)) {
            PushKind.TEST, PushKind.RING_END -> FcmPushHandling.NOTHING

            PushKind.MESSAGE -> FcmPushHandling.DART

            PushKind.RING -> FcmPushHandling.RING

            PushKind.BADGE -> when {
                appInFront -> FcmPushHandling.NOTHING
                data["unread"]?.trim()?.toLongOrNull() == 0L -> FcmPushHandling.CLEAR_MESSAGES
                else -> FcmPushHandling.NOTHING
            }
        }

    fun messageNotificationIds(shown: List<ShownNotification>): List<Int> =
        shown.filter { it.channelId in messageChannels }.map { it.id }
}
