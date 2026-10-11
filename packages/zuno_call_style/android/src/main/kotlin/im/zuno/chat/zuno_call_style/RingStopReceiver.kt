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

            IncomingRing.ACTION_DECLINED -> {
                IncomingRing.stopFor(context, callId, takeDownNotification = true)
                context.sendBroadcast(
                    Intent(intent)
                        .setClassName(context, NOTIFICATION_ACTION_RECEIVER)
                        .setAction(NOTIFICATION_ACTION_TAPPED),
                )
            }
        }
    }

    private companion object {
        const val NOTIFICATION_ACTION_TAPPED =
            "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver.ACTION_TAPPED"
        const val NOTIFICATION_ACTION_RECEIVER =
            "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"
    }
}
