package im.zuno.chat

import im.zuno.chat.zuno_notifications.PushKind
import org.junit.Assert.assertEquals
import org.junit.Test

class PushKindTest {
    @Test
    fun `a zuno test event id is a test push, with or without a room`() {
        assertEquals(PushKind.TEST, PushKind.of("\$zuno_test_1", null))
        assertEquals(PushKind.TEST, PushKind.of("\$zuno_test_1", "!r:x"))
    }

    @Test
    fun `an event id and a room id make a message push`() {
        assertEquals(PushKind.MESSAGE, PushKind.of("\$e", "!r:x"))
    }

    @Test
    fun `a push missing either id is a badge push, as in Dart`() {
        val missing = listOf("\$e" to null, "\$e" to "", null to "!r:x", "" to "!r:x", null to null)
        for ((eventId, roomId) in missing) {
            assertEquals("$eventId / $roomId", PushKind.BADGE, PushKind.of(eventId, roomId))
        }
    }
}
