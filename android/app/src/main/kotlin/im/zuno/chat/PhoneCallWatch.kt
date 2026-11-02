package im.zuno.chat

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import androidx.annotation.RequiresApi

class PhoneCallWatch(private val context: Context, private val onPhoneCall: () -> Unit) {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val telephony by lazy { context.getSystemService(TelephonyManager::class.java) }
    private var listener: Any? = null
    private var inPhoneCall = false

    fun start() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) watchMode() else watchCallState()
    }

    fun stop() {
        val watching = listener ?: return
        listener = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.removeOnModeChangedListener(
                watching as AudioManager.OnModeChangedListener,
            )
        } else {
            @Suppress("DEPRECATION")
            telephony?.listen(watching as PhoneStateListener, PhoneStateListener.LISTEN_NONE)
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun watchMode() {
        inPhoneCall = PhoneCallDecision.isPhoneCallMode(audioManager.mode)
        val modeChanged = object : AudioManager.OnModeChangedListener {
            override fun onModeChanged(mode: Int) {
                if (listener === this) seen(PhoneCallDecision.isPhoneCallMode(mode))
            }
        }
        listener = modeChanged
        audioManager.addOnModeChangedListener(context.mainExecutor, modeChanged)
    }

    @Suppress("DEPRECATION")
    private fun watchCallState() {
        val telephony = telephony ?: return
        inPhoneCall = PhoneCallDecision.isPhoneCallState(telephony.callState)
        val callStateChanged = object : PhoneStateListener() {
            @Suppress("OVERRIDE_DEPRECATION")
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                if (listener === this) seen(PhoneCallDecision.isPhoneCallState(state))
            }
        }
        listener = callStateChanged
        try {
            telephony.listen(callStateChanged, PhoneStateListener.LISTEN_CALL_STATE)
        } catch (error: SecurityException) {
            listener = null
            CaughtErrors.record(context, "phone call watch", error)
        }
    }

    private fun seen(now: Boolean) {
        val started = PhoneCallDecision.phoneCallStarted(
            wasInPhoneCall = inPhoneCall,
            inPhoneCall = now,
        )
        inPhoneCall = now
        if (started) onPhoneCall()
    }
}
