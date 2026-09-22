package im.zuno.chat

import im.zuno.chat.zuno_notifications.CachedRoom
import im.zuno.chat.zuno_notifications.NoticeConversation
import im.zuno.chat.zuno_notifications.NoticeCopy
import im.zuno.chat.zuno_notifications.PushNoticeDecision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PushNoticeDecisionTest {
    @Test
    fun `posts on a cold process for a fresh room`() {
        assertTrue(PushNoticeDecision.shouldPost("!r:x", "\$e", liveEngines = 0, showingForRoom = false))
    }

    @Test
    fun `a live engine means Dart will handle it`() {
        assertFalse(PushNoticeDecision.shouldPost("!r:x", "\$e", liveEngines = 1, showingForRoom = false))
    }

    @Test
    fun `never replaces a thread that is already showing`() {
        assertFalse(PushNoticeDecision.shouldPost("!r:x", "\$e", liveEngines = 0, showingForRoom = true))
    }

    @Test
    fun `badge pushes and malformed data get no notice`() {
        assertFalse(PushNoticeDecision.shouldPost("!r:x", null, 0, false))
        assertFalse(PushNoticeDecision.shouldPost("!r:x", "", 0, false))
        assertFalse(PushNoticeDecision.shouldPost(null, "\$e", 0, false))
        assertFalse(PushNoticeDecision.shouldPost(" ", "\$e", 0, false))
    }

    @Test
    fun `an engine this push booted does not count against the notice`() {
        assertEquals(0, PushNoticeDecision.enginesFor(bootedForThisPush = true, liveEngines = 1))
        assertEquals(1, PushNoticeDecision.enginesFor(bootedForThisPush = false, liveEngines = 1))
        assertEquals(0, PushNoticeDecision.enginesFor(bootedForThisPush = false, liveEngines = 0))
    }

    @Test
    fun `parses the room cache lines and skips malformed ones`() {
        val cache = PushNoticeDecision.parseRoomCache("!a:x\td\tAlice\n!g:x\tg\tFamily chat\nbroken line\n\n!h:x\tq\tOdd")
        assertEquals(CachedRoom("Alice", isDirect = true), cache["!a:x"])
        assertEquals(CachedRoom("Family chat", isDirect = false), cache["!g:x"])
        assertEquals(CachedRoom("Odd", isDirect = false), cache["!h:x"])
        assertEquals(3, cache.size)
        assertTrue(PushNoticeDecision.parseRoomCache(null).isEmpty())
        assertTrue(PushNoticeDecision.parseRoomCache("").isEmpty())
    }

    @Test
    fun `copy uses the room name when known`() {
        assertEquals(NoticeCopy("Alice", "New message"), PushNoticeDecision.copyFor(CachedRoom("Alice", true)))
        assertEquals(NoticeCopy("New message", "Tap to open"), PushNoticeDecision.copyFor(null))
        assertEquals(NoticeCopy("New message", "Tap to open"), PushNoticeDecision.copyFor(CachedRoom("  ", true)))
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
        assertEquals(NoticeConversation("Alice", isGroup = false), PushNoticeDecision.conversationFor(CachedRoom("Alice", true)))
        assertEquals(NoticeConversation("Family", isGroup = true), PushNoticeDecision.conversationFor(CachedRoom(" Family ", false)))
        assertNull(PushNoticeDecision.conversationFor(null))
        assertNull(PushNoticeDecision.conversationFor(CachedRoom("  ", true)))
    }
}
