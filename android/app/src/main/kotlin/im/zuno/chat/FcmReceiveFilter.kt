package im.zuno.chat

data class FcmReceivePlan(
    val postNotice: Boolean,
    val wakeLockKey: String?,
    val warmUpFlutter: Boolean,
)

class FcmReceiveFilter(private val capacity: Int = RECENT_MESSAGE_IDS) {
    private val recent = object : LinkedHashMap<String, Unit>(capacity, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Unit>?): Boolean =
            size > capacity
    }

    @Synchronized
    fun planFor(
        messageType: String?,
        messageId: String?,
        eventPush: Boolean,
        appInFront: Boolean,
    ): FcmReceivePlan? {
        if (messageType != null && messageType != DATA_MESSAGE) return null
        if (messageId != null && recent.put(messageId, Unit) != null) return null
        val background = eventPush && !appInFront
        return FcmReceivePlan(
            postNotice = eventPush,
            wakeLockKey = messageId?.takeIf { background },
            warmUpFlutter = background,
        )
    }

    companion object {
        const val RECENT_MESSAGE_IDS = 32
        private const val DATA_MESSAGE = "gcm"
    }
}
