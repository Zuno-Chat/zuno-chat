package im.zuno.chat

import im.zuno.chat.zuno_call_style.RememberedRing
import im.zuno.chat.zuno_call_style.RingCancel
import im.zuno.chat.zuno_call_style.RingDecisions
import im.zuno.chat.zuno_call_style.RingPlan
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class IncomingRingDecisionsTest {
    private val now = 1_700_000_000_000L

    private fun remembered(callId: String, ageMs: Long = 0) = RememberedRing(callId, now - ageMs)

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
    fun `a timeout or a dismissal stops only the ring it was armed for`() {
        assertTrue(RingDecisions.stops("c1", "c1"))
        assertFalse(RingDecisions.stops("c2", "c1"))
        assertTrue(RingDecisions.stops(null, "c1"))
        assertTrue(RingDecisions.stops("c1", null))
    }

    @Test
    fun `rings with the tone and the buzz the settings ask for`() {
        val plan = RingPlan.from(
            mapOf(
                "ringtone" to true,
                "ringtoneAsset" to "assets/sounds/ringtone.wav",
                "vibrate" to true,
                "vibrationPattern" to listOf(0, 800, 500, 800, 2000),
            ),
        )

        assertEquals("assets/sounds/ringtone.wav", plan.ringtoneAsset)
        assertArrayEquals(longArrayOf(0, 800, 500, 800, 2000), plan.vibrationPattern)
    }

    @Test
    fun `the Ringtone and Vibrate for calls settings each switch off their own half`() {
        val noTone = RingPlan.from(
            mapOf(
                "ringtone" to false,
                "ringtoneAsset" to "a.wav",
                "vibrate" to true,
                "vibrationPattern" to listOf(0, 800),
            ),
        )
        val noBuzz = RingPlan.from(
            mapOf(
                "ringtone" to true,
                "ringtoneAsset" to "a.wav",
                "vibrate" to false,
                "vibrationPattern" to listOf(0, 800),
            ),
        )

        assertNull(noTone.ringtoneAsset)
        assertArrayEquals(longArrayOf(0, 800), noTone.vibrationPattern)
        assertEquals("a.wav", noBuzz.ringtoneAsset)
        assertNull(noBuzz.vibrationPattern)
    }

    @Test
    fun `a ring that misses its settings stays silent rather than guessing`() {
        val bare = RingPlan.from(emptyMap())
        val noAsset = RingPlan.from(mapOf("ringtone" to true, "ringtoneAsset" to " "))

        assertNull(bare.ringtoneAsset)
        assertNull(bare.vibrationPattern)
        assertNull(noAsset.ringtoneAsset)
    }

    @Test
    fun `a pattern the vibrator would reject buzzes nothing instead of failing the ring`() {
        val rejected = listOf<Any?>(
            emptyList<Int>(),
            listOf(0, 0),
            listOf(0, -5, 100),
            listOf(0, "800"),
            listOf(0, null),
            "0,800",
            null,
        )

        for (pattern in rejected) {
            val plan = RingPlan.from(mapOf("vibrate" to true, "vibrationPattern" to pattern))
            assertNull("$pattern", plan.vibrationPattern)
        }
    }

    @Test
    fun `takes a pattern of large numbers as the codec sends them`() {
        val plan = RingPlan.from(mapOf("vibrate" to true, "vibrationPattern" to listOf(0L, 800L)))

        assertArrayEquals(longArrayOf(0, 800), plan.vibrationPattern)
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
    fun `the buzz runs at full strength and its pauses stay silent`() {
        assertArrayEquals(
            intArrayOf(0, 255, 0, 255, 0),
            RingDecisions.amplitudes(longArrayOf(0, 800, 500, 800, 2000)),
        )
    }
}
