package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class PlayServicesDecisionTest {
    @Test
    fun `SUCCESS is available`() {
        assertEquals(
            PlayServicesAvailability.AVAILABLE,
            PlayServicesDecision.decide(0),
        )
    }

    @Test
    fun `SERVICE_MISSING is unavailable`() {
        assertEquals(
            PlayServicesAvailability.UNAVAILABLE,
            PlayServicesDecision.decide(1),
        )
    }

    @Test
    fun `SERVICE_VERSION_UPDATE_REQUIRED is fixable, not absent`() {
        assertEquals(
            PlayServicesAvailability.UPDATE_REQUIRED,
            PlayServicesDecision.decide(2),
        )
    }

    @Test
    fun `SERVICE_DISABLED is unavailable`() {
        assertEquals(
            PlayServicesAvailability.UNAVAILABLE,
            PlayServicesDecision.decide(3),
        )
    }

    @Test
    fun `SERVICE_INVALID is unavailable`() {
        assertEquals(
            PlayServicesAvailability.UNAVAILABLE,
            PlayServicesDecision.decide(9),
        )
    }

    @Test
    fun `SERVICE_UPDATING is fixable — it resolves itself`() {
        assertEquals(
            PlayServicesAvailability.UPDATE_REQUIRED,
            PlayServicesDecision.decide(18),
        )
    }

    @Test
    fun `an unknown code is unavailable, never available`() {
        assertEquals(
            PlayServicesAvailability.UNAVAILABLE,
            PlayServicesDecision.decide(9999),
        )
    }
}
