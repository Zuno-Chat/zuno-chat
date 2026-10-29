package im.zuno.chat

import im.zuno.chat.zuno_notifications.CachedRoom
import im.zuno.chat.zuno_notifications.InstantRingCall
import im.zuno.chat.zuno_notifications.InstantRingDecision
import im.zuno.chat.zuno_notifications.InstantRingOutcome
import im.zuno.chat.zuno_notifications.InstantRingState
import im.zuno.chat.zuno_notifications.RingName
import im.zuno.chat.zuno_notifications.RingText
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class InstantRingDecisionTest {
    private val call = InstantRingCall(
        roomId = "!dm:x",
        callId = "c1",
        callerId = "@alice:x",
        callerName = "Alice",
        roomName = "",
        isVideo = false,
    )

    private val idle = InstantRingState(
        appInFront = false,
        userId = "@me:x",
        resolved = emptySet(),
        showingCallId = null,
        rememberedCallId = null,
        callActive = false,
        room = CachedRoom("Alice Smith", isDirect = true),
        preview = null,
        ringtone = true,
        vibrate = true,
    )

    private fun decide(
        state: InstantRingState = idle,
        ringing: InstantRingCall = call,
        channels: Set<String> = setOf("calls_ringing", "calls_ringing_group"),
    ) = InstantRingDecision.decide(ringing, state) { it in channels }

    private fun shown(outcome: InstantRingOutcome) = (outcome as InstantRingOutcome.Present).look

    private fun skipped(outcome: InstantRingOutcome) = (outcome as InstantRingOutcome.Skip).reason

    @Test
    fun `rings a chat under the partner's name, saying the kind of call, on the ring channel`() {
        val look = shown(decide())

        assertEquals("calls_ringing", look.channelId)
        assertEquals(RingName.Named("Alice Smith"), look.name)
        assertEquals(RingText.Kind, look.text)
        assertEquals("assets/sounds/ringtone.ogg", look.plan.ringtoneAsset)
        assertArrayEquals(longArrayOf(0, 800, 500, 800, 2000), look.plan.vibrationPattern)
    }

    @Test
    fun `rings a group under its name, saying who calls, on the group ring channel`() {
        val look = shown(decide(idle.copy(room = CachedRoom("Climbing club", isDirect = false))))

        assertEquals("calls_ringing_group", look.channelId)
        assertEquals(RingName.Named("Climbing club"), look.name)
        assertEquals(RingText.Caller("Alice"), look.text)
    }

    @Test
    fun `a room the app has not cached yet is named from the ring, as a group`() {
        val named = shown(decide(idle.copy(room = null), call.copy(roomName = "Climbing club")))
        val unnamed = shown(decide(idle.copy(room = null)))

        assertEquals(RingName.Named("Climbing club"), named.name)
        assertEquals(RingText.Caller("Alice"), named.text)
        assertEquals("calls_ringing_group", named.channelId)
        assertEquals(RingName.Named("Alice"), unnamed.name)
    }

    @Test
    fun `with notification content hidden, rings as a generic call of its kind`() {
        val look = shown(
            decide(
                idle.copy(
                    room = CachedRoom("Climbing club", isDirect = false),
                    preview = "nothing",
                ),
            ),
        )

        assertEquals(RingName.Generic, look.name)
        assertEquals(RingText.Kind, look.text)
    }

    @Test
    fun `the Ringtone and Vibrate for calls settings each switch off their own half`() {
        val look = shown(decide(idle.copy(ringtone = false, vibrate = false)))

        assertNull(look.plan.ringtoneAsset)
        assertNull(look.plan.vibrationPattern)
    }

    @Test
    fun `leaves the ring to the app when it is in front`() {
        assertEquals("app_in_front", skipped(decide(idle.copy(appInFront = true))))
    }

    @Test
    fun `does not ring before the app has told it who is signed in`() {
        assertEquals("no_session", skipped(decide(idle.copy(userId = null))))
    }

    @Test
    fun `does not ring for a call I started`() {
        assertEquals("own_call", skipped(decide(ringing = call.copy(callerId = "@me:x"))))
    }

    @Test
    fun `does not ring a call that already rings`() {
        assertEquals(
            "already_rung",
            skipped(decide(idle.copy(showingCallId = "c1", rememberedCallId = "c1"))),
        )
    }

    @Test
    fun `does not ring again a call that rang a moment ago and was declined or answered`() {
        assertEquals("already_rung", skipped(decide(idle.copy(rememberedCallId = "c1"))))
    }

    @Test
    fun `another call that rang a moment ago but no longer shows does not hold this one back`() {
        shown(decide(idle.copy(rememberedCallId = "c0")))
    }

    @Test
    fun `does not ring a call that was already answered, declined or ended`() {
        assertEquals("resolved", skipped(decide(idle.copy(resolved = setOf("c1")))))
    }

    @Test
    fun `does not ring over another call that still rings`() {
        assertEquals(
            "busy_ringing",
            skipped(decide(idle.copy(showingCallId = "c0", rememberedCallId = "c0"))),
        )
    }

    @Test
    fun `rings over a call that rings on though it is over`() {
        shown(decide(idle.copy(showingCallId = "c0", resolved = setOf("c0"))))
    }

    @Test
    fun `leaves a call that comes in during a call to the app, which rings it as waiting`() {
        assertEquals("busy_active", skipped(decide(idle.copy(callActive = true))))
    }

    @Test
    fun `does not ring where its ring cannot show`() {
        assertEquals("cannot_show", skipped(decide(channels = emptySet())))
        assertEquals(
            "cannot_show",
            skipped(
                decide(
                    idle.copy(room = CachedRoom("Climbing club", isDirect = false)),
                    channels = setOf("calls_ringing"),
                ),
            ),
        )
    }

    @Test
    fun `before a call is opened, says whether this phone may ring at once at all`() {
        assertEquals("app_in_front", InstantRingDecision.unavailable(true, "@me:x"))
        assertEquals("no_session", InstantRingDecision.unavailable(false, null))
        assertEquals("no_session", InstantRingDecision.unavailable(false, ""))
        assertNull(InstantRingDecision.unavailable(false, "@me:x"))
    }
}
