package im.zuno.chat

import im.zuno.chat.zuno_notifications.PushKind

sealed interface FcmReceivePlan {
    data object TestNotice : FcmReceivePlan

    data class MessageNotice(val wakeLockKey: String?, val warmUpFlutter: Boolean) : FcmReceivePlan

    data object RingWarmUp : FcmReceivePlan

    data object RingEnd : FcmReceivePlan

    data object RecordOnly : FcmReceivePlan
}

class FcmReceiveFilter(private val capacity: Int = RECENT_MESSAGE_IDS) {
    private val recent = object : LinkedHashMap<String, Long>(capacity, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Long>?): Boolean =
            size > capacity
    }

    @Synchronized
    fun planFor(
        messageType: String?,
        messageId: String?,
        kind: PushKind,
        appInFront: Boolean,
        arrivedAtElapsedMs: Long,
    ): FcmReceivePlan? {
        if (messageType != null && messageType != DATA_MESSAGE) return null
        if (messageId != null && recent.putIfAbsent(messageId, arrivedAtElapsedMs) != null) {
            return null
        }
        return when (kind) {
            PushKind.TEST -> FcmReceivePlan.TestNotice

            PushKind.MESSAGE -> FcmReceivePlan.MessageNotice(
                wakeLockKey = messageId?.takeIf { !appInFront },
                warmUpFlutter = !appInFront,
            )

            PushKind.RING -> FcmReceivePlan.RingWarmUp

            PushKind.RING_END -> FcmReceivePlan.RingEnd

            PushKind.BADGE -> FcmReceivePlan.RecordOnly
        }
    }

    @Synchronized
    fun arrivedAt(messageId: String?): Long? = messageId?.let { recent[it] }

    companion object {
        val shared = FcmReceiveFilter()
        const val RECENT_MESSAGE_IDS = 32
        private const val DATA_MESSAGE = "gcm"
    }
}
