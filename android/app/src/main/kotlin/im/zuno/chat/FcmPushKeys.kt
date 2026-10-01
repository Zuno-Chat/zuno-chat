package im.zuno.chat

object FcmPushKeys {
    fun messageId(raw: String?): String? = raw?.takeIf { it.isNotEmpty() }

    fun shouldForwardToken(registered: String?, fresh: String): Boolean =
        !registered.isNullOrEmpty() && registered != fresh
}
