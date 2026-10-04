package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FcmBadgeDecisionTest {
    private val eventPush = mapOf("event_id" to "\$e", "room_id" to "!r:x", "unread" to "2")

    @Test
    fun `an event push goes to Dart whether or not the app is in front`() {
        assertEquals(FcmPushHandling.DART, FcmBadgeDecision.handlingFor(eventPush, false))
        assertEquals(FcmPushHandling.DART, FcmBadgeDecision.handlingFor(eventPush, true))
    }

    @Test
    fun `a badge push saying everything is read clears the chats natively`() {
        assertEquals(
            FcmPushHandling.CLEAR_MESSAGES,
            FcmBadgeDecision.handlingFor(mapOf("unread" to "0", "prio" to "high"), false),
        )
    }

    @Test
    fun `with the app in front the sync clears read chats, so the badge push does nothing`() {
        assertEquals(
            FcmPushHandling.NOTHING,
            FcmBadgeDecision.handlingFor(mapOf("unread" to "0"), true),
        )
    }

    @Test
    fun `a badge push with unread chats, an unreadable count or no count does nothing`() {
        for (unread in listOf("3", "many", "", "0.0", null)) {
            assertEquals(
                "unread=$unread",
                FcmPushHandling.NOTHING,
                FcmBadgeDecision.handlingFor(
                    mapOf("unread" to unread, "missed_calls" to "0"),
                    false,
                ),
            )
        }
        assertEquals(FcmPushHandling.NOTHING, FcmBadgeDecision.handlingFor(emptyMap(), false))
    }

    @Test
    fun `the zero is read the way Dart's int tryParse reads it`() {
        for (unread in listOf(" 0", "0\n", "+0", "-0", "00")) {
            assertEquals(
                "unread=[$unread]",
                FcmPushHandling.CLEAR_MESSAGES,
                FcmBadgeDecision.handlingFor(mapOf("unread" to unread), false),
            )
        }
    }

    @Test
    fun `a push needs both an event id and a room id to be an event push, as in Dart`() {
        assertTrue(FcmBadgeDecision.isEventPush("\$e", "!r:x"))
        assertFalse(FcmBadgeDecision.isEventPush("\$e", null))
        assertFalse(FcmBadgeDecision.isEventPush("\$e", ""))
        assertFalse(FcmBadgeDecision.isEventPush(null, "!r:x"))
        assertFalse(FcmBadgeDecision.isEventPush("", "!r:x"))
        assertEquals(
            FcmPushHandling.CLEAR_MESSAGES,
            FcmBadgeDecision.handlingFor(mapOf("event_id" to "", "unread" to "0"), false),
        )
    }

    @Test
    fun `the clear takes every chat notification and nothing else`() {
        val shown = listOf(
            ShownNotification(11, "direct_messages"),
            ShownNotification(12, "group_messages"),
            ShownNotification(13, "quiet_messages"),
            ShownNotification(4105, "direct_messages"),
            ShownNotification(21, "incoming_calls"),
            ShownNotification(22, "ongoing_calls"),
            ShownNotification(23, "new_device"),
            ShownNotification(24, null),
        )

        assertEquals(listOf(11, 12, 13, 4105), FcmBadgeDecision.messageNotificationIds(shown))
        assertEquals(emptyList<Int>(), FcmBadgeDecision.messageNotificationIds(emptyList()))
    }

    @Test
    fun `the clear forgets the chat threads Dart keeps in its shared preferences`() {
        assertEquals("flutter.notifications.threads", FcmBadgeDecision.THREADS_KEY)
    }

    @Test
    fun `a test push does nothing for Dart, with or without a room`() {
        val bare = mapOf("event_id" to "\$zuno_test_1")
        val withRoom = mapOf("event_id" to "\$zuno_test_1", "room_id" to "!r:x")
        for (data in listOf(bare, withRoom)) {
            assertEquals(FcmPushHandling.NOTHING, FcmBadgeDecision.handlingFor(data, false))
            assertEquals(FcmPushHandling.NOTHING, FcmBadgeDecision.handlingFor(data, true))
        }
    }
}
