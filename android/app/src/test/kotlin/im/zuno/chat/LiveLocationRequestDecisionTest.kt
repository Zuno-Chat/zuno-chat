package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveLocationRequestDecisionTest {
    @Test
    fun `reads the mode Dart names and nothing else`() {
        assertEquals(LiveLocationMode.Coarse, LiveLocationMode.from("coarse"))
        assertEquals(LiveLocationMode.Precise, LiveLocationMode.from("precise"))
        assertNull(LiveLocationMode.from("gps"))
        assertNull(LiveLocationMode.from(null))
    }

    @Test
    fun `coarse mode skips GPS and wakes every five minutes`() {
        val request = LiveLocationRequestDecision.requestFor(LiveLocationMode.Coarse)

        assertFalse(request.highAccuracy)
        assertEquals(300_000L, request.intervalMs)
        assertEquals(0f, request.minDistanceMeters)
    }

    @Test
    fun `precise mode uses GPS every five seconds`() {
        val request = LiveLocationRequestDecision.requestFor(LiveLocationMode.Precise)

        assertTrue(request.highAccuracy)
        assertEquals(5_000L, request.intervalMs)
    }

    @Test
    fun `prefers the platform's fused provider where it exists`() {
        assertEquals(
            "fused",
            LiveLocationRequestDecision.providerFor(
                LiveLocationMode.Coarse,
                setOf("fused", "gps", "network"),
                sdkInt = 31,
            ),
        )
    }

    @Test
    fun `without a fused provider precise takes GPS and coarse the network`() {
        val enabled = setOf("gps", "network", "fused")

        assertEquals(
            "gps",
            LiveLocationRequestDecision.providerFor(LiveLocationMode.Precise, enabled, sdkInt = 30),
        )
        assertEquals(
            "network",
            LiveLocationRequestDecision.providerFor(LiveLocationMode.Coarse, enabled, sdkInt = 30),
        )
    }

    @Test
    fun `falls back to whatever provider is on, or none`() {
        assertEquals(
            "gps",
            LiveLocationRequestDecision.providerFor(
                LiveLocationMode.Coarse,
                setOf("gps"),
                sdkInt = 34,
            ),
        )
        assertEquals(
            "network",
            LiveLocationRequestDecision.providerFor(
                LiveLocationMode.Precise,
                setOf("network"),
                sdkInt = 34,
            ),
        )
        assertNull(
            LiveLocationRequestDecision.providerFor(
                LiveLocationMode.Precise,
                setOf("passive"),
                sdkInt = 34,
            ),
        )
    }

    @Test
    fun `only the newest fix's handling releases the wake lock`() {
        assertTrue(LiveLocationRequestDecision.releasesWakeLock(handled = 4, newest = 4))
        assertFalse(LiveLocationRequestDecision.releasesWakeLock(handled = 3, newest = 4))
    }

    @Test
    fun `capture outlives the share's end only by a short grace`() {
        val endsAt = 1_000_000L

        assertFalse(LiveLocationRequestDecision.isPastEnd(nowMs = endsAt - 1, endsAtMs = endsAt))
        assertFalse(
            LiveLocationRequestDecision.isPastEnd(nowMs = endsAt + 120_000, endsAtMs = endsAt),
        )
        assertTrue(
            LiveLocationRequestDecision.isPastEnd(nowMs = endsAt + 120_001, endsAtMs = endsAt),
        )
    }
}
