package im.zuno.chat.zuno_notifications

object NotificationIds {
    fun messageNotificationIdFor(roomId: String): Int {
        var hash = 0x811c9dc5.toInt()
        for (byte in roomId.toByteArray(Charsets.UTF_8)) {
            hash = hash xor (byte.toInt() and 0xff)
            hash *= 0x01000193
        }
        return hash and 0x7fffffff
    }
}
