package im.zuno.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val channel = MainActivity.callsChannel
        when (CallHangUpDecision.decide(intent.action, channel != null)) {
            CallHangUpAction.DeliverToDart -> channel?.invokeMethod(HANG_UP_METHOD, null)
            CallHangUpAction.StopService -> CallForegroundService.stop(context)
            CallHangUpAction.Ignore -> Unit
        }
    }

    companion object {
        const val ACTION_HANG_UP = "im.zuno.chat.HANG_UP_CALL"
        const val HANG_UP_METHOD = "hangUpCall"
    }
}
