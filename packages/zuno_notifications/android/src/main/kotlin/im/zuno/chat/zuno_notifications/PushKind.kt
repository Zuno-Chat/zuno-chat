package im.zuno.chat.zuno_notifications

enum class PushKind {
    TEST,
    MESSAGE,
    RING,
    BADGE,
    ;

    companion object {
        private const val TEST_EVENT_PREFIX = "\$zuno_test_"

        fun of(eventId: String?, roomId: String?, ring: Boolean = false): PushKind = when {
            ring -> RING
            eventId?.startsWith(TEST_EVENT_PREFIX) == true -> TEST
            !eventId.isNullOrEmpty() && !roomId.isNullOrEmpty() -> MESSAGE
            else -> BADGE
        }
    }
}
