package im.zuno.chat

import android.media.AudioManager
import android.telephony.TelephonyManager

object PhoneCallDecision {
    fun isPhoneCallMode(mode: Int): Boolean = mode == AudioManager.MODE_IN_CALL

    fun isPhoneCallState(callState: Int): Boolean = callState == TelephonyManager.CALL_STATE_OFFHOOK

    fun phoneCallStarted(wasInPhoneCall: Boolean, inPhoneCall: Boolean): Boolean =
        inPhoneCall && !wasInPhoneCall
}
