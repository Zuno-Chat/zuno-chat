package im.zuno.chat

import im.zuno.chat.zuno_notifications.PushKind

sealed interface FcmReceivePlan {
    data object TestNotice : FcmReceivePlan

    data class MessageNotice(val wakeLockKey: String?, val warmUpFlutter: Boolean) : FcmReceivePlan

    data object RecordOnly : FcmReceivePlan
}

class FcmReceiveFilter(private val capacity: Int = RECENT_MESSAGE_IDS) {
    private val recent = object : LinkedHashMap<String, Unit>(capacity, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Unit>?): Boolean =
            size > capacity
    }

    @Synchronized
    fun planFor(
        messageType: String?,
        messageId: String?,
        kind: PushKind,
        appInFront: Boolean,
    ): FcmReceivePlan? {
        if (messageType != null && messageType != DATA_MESSAGE) return null
        if (messageId != null && recent.put(messageId, Unit) != null) return null
        return when (kind) {
            PushKind.TEST -> FcmReceivePlan.TestNotice

            PushKind.MESSAGE -> FcmReceivePlan.MessageNotice(
                wakeLockKey = messageId?.takeIf { !appInFront },
                warmUpFlutter = !appInFront,
            )

            PushKind.BADGE -> FcmReceivePlan.RecordOnly
        }
    }

    companion object {
        const val RECENT_MESSAGE_IDS = 32
        private const val DATA_MESSAGE = "gcm"
    }
}
