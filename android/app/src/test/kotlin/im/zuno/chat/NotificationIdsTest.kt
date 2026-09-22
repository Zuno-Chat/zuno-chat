package im.zuno.chat

import im.zuno.chat.zuno_notifications.NotificationIds
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationIdsTest {
    @Test
    fun `matches the Dart vectors`() {
        assertEquals(1665439068, NotificationIds.messageNotificationIdFor("!abc:example.org"))
        assertEquals(1329869154, NotificationIds.messageNotificationIdFor("!room:matrix.org"))
        assertEquals(18652613, NotificationIds.messageNotificationIdFor(""))
        assertEquals(1478981488, NotificationIds.messageNotificationIdFor("!ünïcode:example.org"))
    }

    @Test
    fun `never negative`() {
        assertTrue(NotificationIds.messageNotificationIdFor("!x:y") >= 0)
    }
}
