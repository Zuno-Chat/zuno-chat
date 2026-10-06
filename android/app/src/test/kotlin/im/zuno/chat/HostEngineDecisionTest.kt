package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class HostEngineDecisionTest {
    @Test
    fun `keeps the engine when the screen goes away mid-call`() {
        assertEquals(
            HostEngineFate.Keep,
            HostEngineDecision.onHostDetached(callActive = true, adopted = false),
        )
    }

    @Test
    fun `keeps an engine taken over from an earlier screen while the call lasts`() {
        assertEquals(
            HostEngineFate.Keep,
            HostEngineDecision.onHostDetached(callActive = true, adopted = true),
        )
    }

    @Test
    fun `destroys a taken-over engine once no call needs it`() {
        assertEquals(
            HostEngineFate.Destroy,
            HostEngineDecision.onHostDetached(callActive = false, adopted = true),
        )
    }

    @Test
    fun `leaves its own engine to the default without a call`() {
        assertEquals(
            HostEngineFate.Default,
            HostEngineDecision.onHostDetached(callActive = false, adopted = false),
        )
    }
}
