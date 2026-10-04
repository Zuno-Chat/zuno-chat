package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class PushDiagDecisionTest {
    @Test
    fun `each importance level has its own name`() {
        assertEquals("none", PushDiagDecision.importanceName(0, groupBlocked = false))
        assertEquals("min", PushDiagDecision.importanceName(1, groupBlocked = false))
        assertEquals("low", PushDiagDecision.importanceName(2, groupBlocked = false))
        assertEquals("default", PushDiagDecision.importanceName(3, groupBlocked = false))
        assertEquals("high", PushDiagDecision.importanceName(4, groupBlocked = false))
        assertEquals("max", PushDiagDecision.importanceName(5, groupBlocked = false))
    }

    @Test
    fun `a channel in a blocked group is blocked whatever its own level`() {
        assertEquals("none", PushDiagDecision.importanceName(4, groupBlocked = true))
    }

    @Test
    fun `an unspecified or strange level is unknown`() {
        assertEquals("unknown", PushDiagDecision.importanceName(-1000, groupBlocked = false))
        assertEquals("unknown", PushDiagDecision.importanceName(9, groupBlocked = false))
    }

    @Test
    fun `background data reads as allowed, exempt or restricted`() {
        assertEquals("allowed", PushDiagDecision.backgroundDataName(1))
        assertEquals("exempt", PushDiagDecision.backgroundDataName(2))
        assertEquals("restricted", PushDiagDecision.backgroundDataName(3))
        assertEquals("unknown", PushDiagDecision.backgroundDataName(0))
    }
}
