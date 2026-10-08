package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HostEngineDecisionTest {
    @Test
    fun `keeps the engine when the screen goes away while a call or live share needs it`() {
        assertEquals(
            HostEngineFate.Keep,
            HostEngineDecision.onHostDetached(keepAlive = true, adopted = false),
        )
    }

    @Test
    fun `keeps an engine taken over from an earlier screen while it is still needed`() {
        assertEquals(
            HostEngineFate.Keep,
            HostEngineDecision.onHostDetached(keepAlive = true, adopted = true),
        )
    }

    @Test
    fun `destroys a taken-over engine once nothing needs it`() {
        assertEquals(
            HostEngineFate.Destroy,
            HostEngineDecision.onHostDetached(keepAlive = false, adopted = true),
        )
    }

    @Test
    fun `leaves its own engine to the default when nothing needs it`() {
        assertEquals(
            HostEngineFate.Default,
            HostEngineDecision.onHostDetached(keepAlive = false, adopted = false),
        )
    }

    @Test
    fun `stays kept while any reason holds it`() {
        val reasons = EngineKeepReasons()

        reasons.hold(EngineKeepReason.Call)
        reasons.hold(EngineKeepReason.LiveLocation)
        reasons.release(EngineKeepReason.Call)

        assertEquals(true, reasons.any)
        reasons.release(EngineKeepReason.LiveLocation)
        assertEquals(false, reasons.any)
    }

    @Test
    fun `releasing a reason never held changes nothing`() {
        val reasons = EngineKeepReasons()
        reasons.hold(EngineKeepReason.Call)

        reasons.release(EngineKeepReason.LiveLocation)

        assertEquals(true, reasons.any)
    }

    @Test
    fun `a live location share alone is not a call`() {
        val reasons = EngineKeepReasons()
        reasons.hold(EngineKeepReason.LiveLocation)
        assertFalse(reasons.holds(EngineKeepReason.Call))

        reasons.hold(EngineKeepReason.Call)
        assertTrue(reasons.holds(EngineKeepReason.Call))
    }
}
