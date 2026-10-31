package im.zuno.chat.zuno_notifications

enum class PushKind {
    TEST,
    MESSAGE,
    RING,
    RING_END,
    BADGE,
    ;

    companion object {
        private const val TEST_EVENT_PREFIX = "\$zuno_test_"

        fun of(
            eventId: String?,
            roomId: String?,
            ring: Boolean = false,
            ringEnd: Boolean = false,
        ): PushKind = when {
            ringEnd -> RING_END
            ring -> RING
            eventId?.startsWith(TEST_EVENT_PREFIX) == true -> TEST
            !eventId.isNullOrEmpty() && !roomId.isNullOrEmpty() -> MESSAGE
            else -> BADGE
        }
    }
}
