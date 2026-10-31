package im.zuno.chat

import im.zuno.chat.zuno_notifications.CachedRoom
import im.zuno.chat.zuno_notifications.NoticeAlert
import im.zuno.chat.zuno_notifications.NoticeConversation
import im.zuno.chat.zuno_notifications.NoticeCopy
import im.zuno.chat.zuno_notifications.NoticePresentation
import im.zuno.chat.zuno_notifications.NoticeText
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
    fun `a call ringing in a one-to-one chat stands in for that chat's notice`() {
        assertTrue(
            PushNoticeDecision.ringStandsIn(CachedRoom("Ana", isDirect = true), "!r:x", "!r:x"),
        )
    }

    @Test
    fun `only a one-to-one chat the app knows can have a ring stand in for its notice`() {
        assertTrue(PushNoticeDecision.ringCanStandIn(CachedRoom("Ana", isDirect = true)))
        assertFalse(PushNoticeDecision.ringCanStandIn(CachedRoom("Hike", isDirect = false)))
        assertFalse(PushNoticeDecision.ringCanStandIn(null))
    }

    @Test
    fun `a ring never stands in for a group's notice, which may be someone else's message`() {
        assertFalse(
            PushNoticeDecision.ringStandsIn(CachedRoom("Hike", isDirect = false), "!r:x", "!r:x"),
        )
    }

    @Test
    fun `a ring stands in only for its own chat, and only for a chat the app knows`() {
        assertFalse(
            PushNoticeDecision.ringStandsIn(CachedRoom("Ana", isDirect = true), "!r:x", "!other:x"),
        )
        assertFalse(
            PushNoticeDecision.ringStandsIn(CachedRoom("Ana", isDirect = true), "!r:x", null),
        )
        assertFalse(PushNoticeDecision.ringStandsIn(null, "!r:x", "!r:x"))
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
            NoticeCopy(NoticeText.Room("Alice"), NoticeText.NewMessage),
            PushNoticeDecision.copyFor(CachedRoom("Alice", true)),
        )
        assertEquals(
            NoticeCopy(NoticeText.NewMessage, NoticeText.TapToOpen),
            PushNoticeDecision.copyFor(null),
        )
        assertEquals(
            NoticeCopy(NoticeText.NewMessage, NoticeText.TapToOpen),
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
    fun `with message tone and vibration on, a notice sounds and vibrates`() {
        assertEquals(
            NoticeAlert(silent = false, vibrate = true),
            PushNoticeDecision.alertFor(messageTone = true, messageVibration = true),
        )
    }

    @Test
    fun `message tone off makes a notice silent, and vibration follows its own setting`() {
        assertEquals(
            NoticeAlert(silent = true, vibrate = true),
            PushNoticeDecision.alertFor(messageTone = false, messageVibration = true),
        )
    }

    @Test
    fun `message vibration off never vibrates, whatever the tone`() {
        assertEquals(
            NoticeAlert(silent = false, vibrate = false),
            PushNoticeDecision.alertFor(messageTone = true, messageVibration = false),
        )
        assertEquals(
            NoticeAlert(silent = true, vibrate = false),
            PushNoticeDecision.alertFor(messageTone = false, messageVibration = false),
        )
    }

    @Test
    fun `at Nothing a notice names no room, holds no conversation and binds no shortcut`() {
        assertEquals(
            NoticePresentation(
                NoticeCopy(NoticeText.Brand, NoticeText.NewMessage),
                conversation = null,
                shortcut = false,
            ),
            PushNoticeDecision.presentationFor(CachedRoom("Family", false), "nothing"),
        )
    }

    @Test
    fun `any other level, or none chosen, shows the cached room as a conversation`() {
        for (preview in listOf("full", "nameOnly", null, "bogus")) {
            assertEquals(
                preview,
                NoticePresentation(
                    NoticeCopy(NoticeText.Room("Family"), NoticeText.NewMessage),
                    NoticeConversation("Family", isGroup = true),
                    shortcut = true,
                ),
                PushNoticeDecision.presentationFor(CachedRoom("Family", false), preview),
            )
        }
    }

    @Test
    fun `an unknown room still binds its shortcut below Nothing`() {
        assertEquals(
            NoticePresentation(
                NoticeCopy(NoticeText.NewMessage, NoticeText.TapToOpen),
                conversation = null,
                shortcut = true,
            ),
            PushNoticeDecision.presentationFor(null, "nameOnly"),
        )
    }
}
