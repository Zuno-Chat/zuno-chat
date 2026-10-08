package im.zuno.chat.zuno_notifications

data class CachedRoom(val name: String, val isDirect: Boolean)

data class NoticeCopy(val title: String, val text: String)

data class NoticeConversation(val title: String, val isGroup: Boolean)

data class NoticeAlert(val silent: Boolean, val vibrate: Boolean)

object PushNoticeDecision {
    const val DIRECT_CHANNEL = "direct_messages"
    const val GROUP_CHANNEL = "group_messages"
    const val MENTIONS_ONLY = "mentionsOnly"

    fun shouldPost(
        roomId: String?,
        eventId: String?,
        appInFront: Boolean,
        showingForRoom: Boolean,
    ): Boolean =
        !roomId.isNullOrBlank() && !eventId.isNullOrBlank() && !appInFront && !showingForRoom

    fun parseRoomCache(text: String?): Map<String, CachedRoom> {
        if (text.isNullOrEmpty()) return emptyMap()
        val rooms = HashMap<String, CachedRoom>()
        for (line in text.lineSequence()) {
            val parts = line.split('\t', limit = 3)
            if (parts.size != 3 || parts[0].isBlank()) continue
            rooms[parts[0]] = CachedRoom(parts[2], isDirect = parts[1] == "d")
        }
        return rooms
    }

    fun copyFor(room: CachedRoom?): NoticeCopy {
        val name = room?.name?.trim().orEmpty()
        return if (name.isEmpty()) {
            NoticeCopy(
                "New message",
                "Tap to open",
            )
        } else {
            NoticeCopy(name, "New message")
        }
    }

    fun channelFor(room: CachedRoom?): String =
        if (room?.isDirect == false) GROUP_CHANNEL else DIRECT_CHANNEL

    fun mutedByNotifyMe(notifyMe: String?): Boolean = notifyMe == MENTIONS_ONLY

    fun shouldPostMissed(notificationsEnabled: Boolean, channelExists: Boolean): Boolean =
        notificationsEnabled && channelExists

    fun alertFor(messageTone: Boolean, messageVibration: Boolean): NoticeAlert =
        NoticeAlert(silent = !messageTone, vibrate = messageVibration)

    fun conversationFor(room: CachedRoom?): NoticeConversation? {
        if (room == null) return null
        val name = room.name.trim()
        if (name.isEmpty()) return null
        return NoticeConversation(name, isGroup = !room.isDirect)
    }
}
