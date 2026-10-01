package im.zuno.chat.zuno_call_style

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class RingStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val callId = intent.getStringExtra(IncomingRing.EXTRA_CALL_ID)
        when (intent.action) {
            IncomingRing.ACTION_TIMED_OUT ->
                IncomingRing.stopFor(context, callId, takeDownNotification = true)

            IncomingRing.ACTION_DISMISSED ->
                IncomingRing.stopFor(context, callId, takeDownNotification = false)
        }
    }
}
