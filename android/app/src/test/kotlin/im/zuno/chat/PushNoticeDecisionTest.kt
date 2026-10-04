package im.zuno.chat

import im.zuno.chat.zuno_notifications.CachedRoom
import im.zuno.chat.zuno_notifications.NoticeConversation
import im.zuno.chat.zuno_notifications.NoticeCopy
import im.zuno.chat.zuno_notifications.PushNoticeDecision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PushNoticeDecisionTest {
    @Test
    fun `posts while the app is not in front`() {
        assertTrue(
            PushNoticeDecision.shouldPost(
                "!r:x",
                "\$e",
                appInFront = false,
                showingForRoom = false,
            ),
        )
    }

    @Test
    fun `the app in front handles its own pushes`() {
        assertFalse(
            PushNoticeDecision.shouldPost("!r:x", "\$e", appInFront = true, showingForRoom = false),
        )
    }

    @Test
    fun `never replaces a thread that is already showing`() {
        assertFalse(
            PushNoticeDecision.shouldPost("!r:x", "\$e", appInFront = false, showingForRoom = true),
        )
    }

    @Test
    fun `badge pushes and malformed data get no notice`() {
        assertFalse(PushNoticeDecision.shouldPost("!r:x", null, false, false))
        assertFalse(PushNoticeDecision.shouldPost("!r:x", "", false, false))
        assertFalse(PushNoticeDecision.shouldPost(null, "\$e", false, false))
        assertFalse(PushNoticeDecision.shouldPost(" ", "\$e", false, false))
    }

    @Test
    fun `parses the room cache lines and skips malformed ones`() {
        val cache = PushNoticeDecision.parseRoomCache(
            "!a:x\td\tAlice\n!g:x\tg\tFamily chat\nbroken line\n\n!h:x\tq\tOdd",
        )
        assertEquals(CachedRoom("Alice", isDirect = true), cache["!a:x"])
        assertEquals(CachedRoom("Family chat", isDirect = false), cache["!g:x"])
        assertEquals(CachedRoom("Odd", isDirect = false), cache["!h:x"])
        assertEquals(3, cache.size)
        assertTrue(PushNoticeDecision.parseRoomCache(null).isEmpty())
        assertTrue(PushNoticeDecision.parseRoomCache("").isEmpty())
    }

    @Test
    fun `copy uses the room name when known`() {
        assertEquals(
            NoticeCopy("Alice", "New message"),
            PushNoticeDecision.copyFor(CachedRoom("Alice", true)),
        )
        assertEquals(NoticeCopy("New message", "Tap to open"), PushNoticeDecision.copyFor(null))
        assertEquals(
            NoticeCopy("New message", "Tap to open"),
            PushNoticeDecision.copyFor(CachedRoom("  ", true)),
        )
    }

    @Test
    fun `channel follows the chat kind, direct when unknown`() {
        assertEquals("direct_messages", PushNoticeDecision.channelFor(CachedRoom("Alice", true)))
        assertEquals("group_messages", PushNoticeDecision.channelFor(CachedRoom("Family", false)))
        assertEquals("direct_messages", PushNoticeDecision.channelFor(null))
    }

    @Test
    fun `mentions only mutes every instant notice, anything else allows it`() {
        assertTrue(PushNoticeDecision.mutedByNotifyMe("mentionsOnly"))
        assertFalse(PushNoticeDecision.mutedByNotifyMe("all"))
        assertFalse(PushNoticeDecision.mutedByNotifyMe(null))
    }

    @Test
    fun `a known room becomes a conversation, an unknown or blank one does not`() {
        assertEquals(
            NoticeConversation("Alice", isGroup = false),
            PushNoticeDecision.conversationFor(CachedRoom("Alice", true)),
        )
        assertEquals(
            NoticeConversation("Family", isGroup = true),
            PushNoticeDecision.conversationFor(CachedRoom(" Family ", false)),
        )
        assertNull(PushNoticeDecision.conversationFor(null))
        assertNull(PushNoticeDecision.conversationFor(CachedRoom("  ", true)))
    }

    @Test
    fun `a missed-pushes notice needs notifications on and its channel created`() {
        assertTrue(
            PushNoticeDecision.shouldPostMissed(notificationsEnabled = true, channelExists = true),
        )
        assertFalse(
            PushNoticeDecision.shouldPostMissed(notificationsEnabled = false, channelExists = true),
        )
        assertFalse(
            PushNoticeDecision.shouldPostMissed(notificationsEnabled = true, channelExists = false),
        )
    }

    @Test
    fun `a zuno test event id is a test push`() {
        assertTrue(PushNoticeDecision.isTestPush("\$zuno_test_1"))
    }

    @Test
    fun `normal, missing and empty event ids are not test pushes`() {
        assertFalse(PushNoticeDecision.isTestPush("\$abc"))
        assertFalse(PushNoticeDecision.isTestPush(null))
        assertFalse(PushNoticeDecision.isTestPush(""))
    }
}
