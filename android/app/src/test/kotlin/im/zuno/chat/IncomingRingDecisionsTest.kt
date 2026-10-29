package im.zuno.chat

import android.app.NotificationManager
import im.zuno.chat.zuno_notifications.FlutterStore
import im.zuno.chat.zuno_notifications.IncomingCallSpec
import im.zuno.chat.zuno_notifications.RememberedRing
import im.zuno.chat.zuno_notifications.RingCancel
import im.zuno.chat.zuno_notifications.RingDecisions
import im.zuno.chat.zuno_notifications.RingPlan
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class IncomingRingDecisionsTest {
    private val now = 1_700_000_000_000L

    private val appRing = mapOf<String, Any?>(
        "channelId" to "calls_ringing",
        "name" to "Ana",
        "callerId" to "@ana:x",
        "isVideo" to true,
        "roomId" to "!r:x",
        "callId" to "c1",
    )

    private fun remembered(callId: String, ageMs: Long = 0) = RememberedRing(callId, now - ageMs)

    private fun ringMsFrom(ringMs: Any?): Long =
        IncomingCallSpec.from(appRing + ("ringMs" to ringMs))!!.ringMs

    @Test
    fun `a cancel for the ringing call forgets it and takes it down`() {
        assertEquals(
            RingCancel(forget = true, dismiss = true),
            RingDecisions.cancel("c1", "c1", remembered("c1"), now),
        )
    }

    @Test
    fun `a cancel for another call leaves the ringing call and its record alone`() {
        assertEquals(
            RingCancel(forget = false, dismiss = false),
            RingDecisions.cancel("c1", "c2", remembered("c2"), now),
        )
    }

    @Test
    fun `a cancel never takes down another call ringing here, even if the record names this one`() {
        assertEquals(
            RingCancel(forget = true, dismiss = false),
            RingDecisions.cancel("c1", "c2", remembered("c1"), now),
        )
    }

    @Test
    fun `a cancel for the ringing call keeps the record of a call about to ring`() {
        assertEquals(
            RingCancel(forget = false, dismiss = true),
            RingDecisions.cancel("c1", "c1", remembered("c2"), now),
        )
    }

    @Test
    fun `with nothing ringing in this process, the record decides`() {
        assertEquals(
            RingCancel(forget = true, dismiss = true),
            RingDecisions.cancel("c1", null, remembered("c1"), now),
        )
        assertEquals(
            RingCancel(forget = false, dismiss = false),
            RingDecisions.cancel("c1", null, remembered("c2"), now),
        )
        assertEquals(
            RingCancel(forget = true, dismiss = true),
            RingDecisions.cancel("c1", null, null, now),
        )
    }

    @Test
    fun `a record of another call older than 45 seconds holds nothing back`() {
        assertEquals(
            RingCancel(forget = true, dismiss = true),
            RingDecisions.cancel("c1", null, remembered("c2", ageMs = 45_001), now),
        )
        assertEquals(
            RingCancel(forget = false, dismiss = false),
            RingDecisions.cancel("c1", null, remembered("c2", ageMs = 45_000), now),
        )
    }

    @Test
    fun `a ring on screen counts as showing for as long as it rings`() {
        assertEquals("c1", RingDecisions.showingRing(true, remembered("c1")))
        assertEquals("c1", RingDecisions.showingRing(true, remembered("c1", ageMs = 59_999)))
    }

    @Test
    fun `nothing counts as showing without its notification on screen or a record`() {
        assertNull(RingDecisions.showingRing(false, remembered("c1")))
        assertNull(RingDecisions.showingRing(true, null))
    }

    @Test
    fun `a ring no longer on screen is remembered for 45 seconds only`() {
        assertEquals("c1", RingDecisions.remembersRing(remembered("c1", ageMs = 45_000), now))
        assertNull(RingDecisions.remembersRing(remembered("c1", ageMs = 45_001), now))
    }

    @Test
    fun `a cancel naming no call forgets and takes down whatever rings`() {
        assertEquals(
            RingCancel(forget = true, dismiss = true),
            RingDecisions.cancel(null, "c2", remembered("c2"), now),
        )
    }

    @Test
    fun `reads a record the way the app writes it, and nothing else`() {
        assertEquals(RememberedRing("c1", 42L), RememberedRing.of("!r:x", "c1", 42))
        assertEquals(
            RememberedRing("c1", 1_700_000_000_000L),
            RememberedRing.of("!r:x", "c1", 1_700_000_000_000L),
        )
        assertNull(RememberedRing.of(null, "c1", 42))
        assertNull(RememberedRing.of("!r:x", null, 42))
        assertNull(RememberedRing.of("!r:x", 7, 42))
        assertNull(RememberedRing.of("!r:x", "c1", "42"))
        assertNull(RememberedRing.of("!r:x", "c1", 42.5))
        assertNull(RememberedRing.of("!r:x", "c1", null))
    }

    @Test
    fun `a ring shows only where Android will show its notification`() {
        assertTrue(RingDecisions.canRing(true, channelImportance = 5, groupBlocked = false))
        assertTrue(RingDecisions.canRing(true, channelImportance = 2, groupBlocked = false))
    }

    @Test
    fun `a ring stays silent with notifications off or its channel or group blocked or missing`() {
        assertFalse(RingDecisions.canRing(false, channelImportance = 5, groupBlocked = false))
        assertFalse(RingDecisions.canRing(true, channelImportance = null, groupBlocked = false))
        assertFalse(RingDecisions.canRing(true, channelImportance = 0, groupBlocked = false))
        assertFalse(RingDecisions.canRing(true, channelImportance = 5, groupBlocked = true))
    }

    @Test
    fun `the app's ring reads its call and rings for the full ring time`() {
        val spec = IncomingCallSpec.from(appRing)!!

        assertEquals("calls_ringing", spec.channelId)
        assertEquals("Ana", spec.name)
        assertEquals("@ana:x", spec.callerId)
        assertEquals("!r:x", spec.roomId)
        assertEquals("c1", spec.callId)
        assertTrue(spec.isVideo)
        assertEquals(60_000L, spec.ringMs)
    }

    @Test
    fun `the app's ring rings only as long as its push allows`() {
        assertEquals(20_000L, ringMsFrom(20_000))
        assertEquals(20_000L, ringMsFrom(20_000L))
        assertEquals(20_000L, ringMsFrom(20_000.4))
        assertEquals(60_000L, ringMsFrom(90_000L))
        assertEquals(1L, ringMsFrom(0))
        assertEquals(1L, ringMsFrom(-5_000))
    }

    @Test
    fun `a ring time that is missing or not a number rings for the full ring time`() {
        assertEquals(60_000L, IncomingCallSpec.from(appRing)!!.ringMs)
        assertEquals(60_000L, ringMsFrom(null))
        assertEquals(60_000L, ringMsFrom("20000"))
        assertEquals(60_000L, ringMsFrom(Double.NaN))
    }

    @Test
    fun `the app's ring without its channel, room or call shows nothing`() {
        for (key in listOf("channelId", "roomId", "callId")) {
            assertNull(key, IncomingCallSpec.from(appRing - key))
            assertNull(key, IncomingCallSpec.from(appRing + (key to 7)))
        }
    }

    @Test
    fun `a timeout or a dismissal stops only the ring it was armed for`() {
        assertTrue(RingDecisions.stops("c1", "c1"))
        assertFalse(RingDecisions.stops("c2", "c1"))
        assertTrue(RingDecisions.stops(null, "c1"))
        assertTrue(RingDecisions.stops("c1", null))
    }

    @Test
    fun `rings with the app's tone and the call buzz the settings ask for`() {
        val plan = RingPlan.from(mapOf("ringtone" to true, "vibrate" to true))

        assertEquals("assets/sounds/ringtone.ogg", plan.ringtoneAsset)
        assertArrayEquals(longArrayOf(0, 800, 500, 800, 2000), plan.vibrationPattern)
    }

    @Test
    fun `a waiting ring holds its ringtone back until it rings aloud, and buzzes at once`() {
        val plan = RingPlan.from(
            mapOf(
                "ringtone" to true,
                "vibrate" to true,
                "waitingText" to "Answering ends your current call",
            ),
        )

        assertNull(plan.toneNow)
        assertEquals("assets/sounds/ringtone.ogg", plan.ringtoneAsset)
        assertTrue(plan.waiting)
        assertEquals("Answering ends your current call", plan.waitingText)
    }

    @Test
    fun `a normal ring plays its ringtone at once`() {
        val plan = RingPlan.of(ringtone = true, vibrate = false)

        assertEquals("assets/sounds/ringtone.ogg", plan.toneNow)
        assertFalse(plan.waiting)
    }

    @Test
    fun `the Ringtone and Vibrate for calls settings each switch off their own half`() {
        val noTone = RingPlan.of(ringtone = false, vibrate = true)
        val noBuzz = RingPlan.of(ringtone = true, vibrate = false)

        assertNull(noTone.ringtoneAsset)
        assertArrayEquals(longArrayOf(0, 800, 500, 800, 2000), noTone.vibrationPattern)
        assertEquals("assets/sounds/ringtone.ogg", noBuzz.ringtoneAsset)
        assertNull(noBuzz.vibrationPattern)
    }

    @Test
    fun `a silent ring channel rings without a tone, an alerting one with it`() {
        assertFalse(RingDecisions.ringsAloud(NotificationManager.IMPORTANCE_MIN))
        assertFalse(RingDecisions.ringsAloud(NotificationManager.IMPORTANCE_LOW))
        assertTrue(RingDecisions.ringsAloud(NotificationManager.IMPORTANCE_DEFAULT))
        assertTrue(RingDecisions.ringsAloud(NotificationManager.IMPORTANCE_HIGH))
        assertFalse(RingDecisions.ringsAloud(null))
    }

    @Test
    fun `a quiet ring drops its tones and keeps its buzz and its waiting line`() {
        val quiet = RingPlan.of(
            ringtone = true,
            vibrate = true,
            waitingText = "Answering ends your call",
        ).quiet()

        assertNull(quiet.ringtoneAsset)
        assertNull(quiet.toneNow)
        assertArrayEquals(longArrayOf(0, 800, 500, 800, 2000), quiet.vibrationPattern)
        assertEquals("Answering ends your call", quiet.waitingText)
    }

    @Test
    fun `a ring that misses its settings stays silent rather than guessing`() {
        val bare = RingPlan.from(emptyMap())

        assertNull(bare.ringtoneAsset)
        assertNull(bare.vibrationPattern)
    }

    @Test
    fun `every ring gets its own copy of the buzz`() {
        val first = RingPlan.of(ringtone = false, vibrate = true)
        first.vibrationPattern!![1] = 0

        assertArrayEquals(
            longArrayOf(0, 800, 500, 800, 2000),
            RingPlan.of(ringtone = false, vibrate = true).vibrationPattern,
        )
    }

    @Test
    fun `a call resolved in the last five minutes counts, older ones and other keys do not`() {
        val now = 1_700_000_000_000L
        val stored = mapOf<String, Any?>(
            "${FlutterStore.RESOLVED_CALL_PREFIX}c1" to now - 60_000L,
            "${FlutterStore.RESOLVED_CALL_PREFIX}c2" to now - 301_000L,
            "${FlutterStore.RESOLVED_CALL_PREFIX}c3" to "soon",
            FlutterStore.RINGING_CALL to now,
        )

        assertEquals(setOf("c1"), RingDecisions.resolvedCallIds(stored, now))
    }

    @Test
    fun `only the ring's Answer button counts as answering`() {
        val select = "SELECT_FOREGROUND_NOTIFICATION"

        assertTrue(RingDecisions.answered(select, 4002, "accept"))
        assertFalse(RingDecisions.answered(select, 4002, null))
        assertFalse(RingDecisions.answered(select, 4002, "decline"))
        assertFalse(RingDecisions.answered(select, 1234, "accept"))
        assertFalse(RingDecisions.answered("android.intent.action.MAIN", 4002, "accept"))
        assertFalse(RingDecisions.answered(null, 4002, "accept"))
    }

    @Test
    fun `a ring launch passes only with the token of the ring being shown`() {
        assertTrue(RingDecisions.tokenMatches(presented = "t1", ringToken = "t1"))
        assertFalse(RingDecisions.tokenMatches(presented = "t2", ringToken = "t1"))
        assertFalse(RingDecisions.tokenMatches(presented = null, ringToken = "t1"))
        assertFalse(RingDecisions.tokenMatches(presented = "t1", ringToken = null))
        assertFalse(RingDecisions.tokenMatches(presented = null, ringToken = null))
    }

    @Test
    fun `every launch the app could read as a ring must prove it came from one`() {
        val select = "SELECT_FOREGROUND_NOTIFICATION"
        val tap = "SELECT_NOTIFICATION"

        assertTrue(RingDecisions.claimsRing(select, 4002, null))
        assertTrue(RingDecisions.claimsRing(select, 4002, "accept"))
        assertTrue(RingDecisions.claimsRing(select, 1234, "accept"))
        assertTrue(RingDecisions.claimsRing(select, -1, "decline"))
        assertTrue(RingDecisions.claimsRing(tap, 1234, "accept"))
        assertTrue(RingDecisions.claimsRing(tap, 4002, null))
    }

    @Test
    fun `a message tap or a plain launch needs no ring token`() {
        assertFalse(RingDecisions.claimsRing("SELECT_NOTIFICATION", 1234, null))
        assertFalse(RingDecisions.claimsRing("SELECT_FOREGROUND_NOTIFICATION", 1234, "mark_read"))
        assertFalse(RingDecisions.claimsRing("android.intent.action.MAIN", 4002, "accept"))
        assertFalse(RingDecisions.claimsRing(null, 4002, "accept"))
    }

    @Test
    fun `only the ring's own launches may show over the lock screen`() {
        val select = "SELECT_FOREGROUND_NOTIFICATION"

        assertTrue(RingDecisions.ringLaunch(select, 4002))
        assertFalse(RingDecisions.ringLaunch(select, 1234))
        assertFalse(RingDecisions.ringLaunch("SELECT_NOTIFICATION", 4002))
        assertFalse(RingDecisions.ringLaunch("im.zuno.chat.OPEN_CALL", -1))
        assertFalse(RingDecisions.ringLaunch(null, 4002))
    }
}
