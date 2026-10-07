package im.zuno.chat.zuno_notifications

enum class PushKind {
    TEST,
    MESSAGE,
    BADGE,
    ;

    companion object {
        private const val TEST_EVENT_PREFIX = "\$zuno_test_"

        fun of(eventId: String?, roomId: String?): PushKind = when {
            eventId?.startsWith(TEST_EVENT_PREFIX) == true -> TEST
            !eventId.isNullOrEmpty() && !roomId.isNullOrEmpty() -> MESSAGE
            else -> BADGE
        }
    }
}
