package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class FcmAvailabilityDecisionTest {
    @Test
    fun `a configured build on a device with working Google Play services is available`() {
        assertEquals(FcmAvailability.AVAILABLE, FcmAvailabilityDecision.decide(true, 0))
    }

    @Test
    fun `an outdated or updating Google Play services needs an update`() {
        for (code in listOf(2, 18)) {
            assertEquals(
                "code $code",
                FcmAvailability.UPDATE_REQUIRED,
                FcmAvailabilityDecision.decide(true, code),
            )
        }
    }

    @Test
    fun `a turned-off Google Play services is told apart from a missing one`() {
        assertEquals(FcmAvailability.DISABLED, FcmAvailabilityDecision.decide(true, 3))
    }

    @Test
    fun `missing, invalid or permission-less Google Play services is unavailable`() {
        for (code in listOf(1, 9, 19)) {
            assertEquals(
                "code $code",
                FcmAvailability.UNAVAILABLE,
                FcmAvailabilityDecision.decide(true, code),
            )
        }
    }

    @Test
    fun `a failed check or an undocumented code is unknown, not unavailable`() {
        for (code in listOf(FcmAvailabilityDecision.CHECK_FAILED, 9999)) {
            assertEquals(
                "code $code",
                FcmAvailability.UNKNOWN,
                FcmAvailabilityDecision.decide(true, code),
            )
        }
    }

    @Test
    fun `a build whose Firebase setup could not be read is unknown, whatever the device has`() {
        for (code in listOf(0, 1, 2, 3)) {
            assertEquals(
                "code $code",
                FcmAvailability.UNKNOWN,
                FcmAvailabilityDecision.decide(null, code),
            )
        }
    }

    @Test
    fun `a build without Firebase config is not configured, whatever the device has`() {
        for (code in listOf(0, 1, 2, 3, FcmAvailabilityDecision.CHECK_FAILED)) {
            assertEquals(
                "code $code",
                FcmAvailability.NOT_CONFIGURED,
                FcmAvailabilityDecision.decide(false, code),
            )
        }
    }

    @Test
    fun `the wire names match what Dart parses`() {
        assertEquals(
            listOf(
                "available",
                "updateRequired",
                "disabled",
                "unavailable",
                "notConfigured",
                "unknown",
            ),
            FcmAvailability.entries.map { it.wire },
        )
    }
}
