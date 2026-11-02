package im.zuno.chat

import android.media.AudioManager
import android.telephony.TelephonyManager
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneCallDecisionTest {
    @Test
    fun `the phone's in-call audio mode means a phone call is on`() {
        assertTrue(PhoneCallDecision.isPhoneCallMode(AudioManager.MODE_IN_CALL))
    }

    @Test
    fun `a voice app's call, a ringing phone or call screening is not a phone call`() {
        assertFalse(PhoneCallDecision.isPhoneCallMode(AudioManager.MODE_IN_COMMUNICATION))
        assertFalse(PhoneCallDecision.isPhoneCallMode(AudioManager.MODE_RINGTONE))
        assertFalse(PhoneCallDecision.isPhoneCallMode(AudioManager.MODE_CALL_SCREENING))
        assertFalse(PhoneCallDecision.isPhoneCallMode(AudioManager.MODE_NORMAL))
    }

    @Test
    fun `an answered or dialing phone call is off hook`() {
        assertTrue(PhoneCallDecision.isPhoneCallState(TelephonyManager.CALL_STATE_OFFHOOK))
    }

    @Test
    fun `a ringing or idle phone is not a phone call`() {
        assertFalse(PhoneCallDecision.isPhoneCallState(TelephonyManager.CALL_STATE_RINGING))
        assertFalse(PhoneCallDecision.isPhoneCallState(TelephonyManager.CALL_STATE_IDLE))
    }

    @Test
    fun `a phone call that starts during the call takes it over`() {
        assertTrue(PhoneCallDecision.phoneCallStarted(wasInPhoneCall = false, inPhoneCall = true))
    }

    @Test
    fun `a phone call already on when the call started never ends it`() {
        assertFalse(PhoneCallDecision.phoneCallStarted(wasInPhoneCall = true, inPhoneCall = true))
    }

    @Test
    fun `a phone call ending, or no phone call at all, never ends the call`() {
        assertFalse(PhoneCallDecision.phoneCallStarted(wasInPhoneCall = true, inPhoneCall = false))
        assertFalse(PhoneCallDecision.phoneCallStarted(wasInPhoneCall = false, inPhoneCall = false))
    }
}
