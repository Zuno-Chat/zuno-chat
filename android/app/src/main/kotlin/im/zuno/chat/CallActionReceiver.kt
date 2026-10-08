package im.zuno.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val channel = AppEngine.callsChannel
        when (ServiceActionDecision.route(intent.action, ACTION_HANG_UP, channel != null)) {
            ServiceActionRoute.DeliverToDart -> channel?.invokeMethod(HANG_UP_METHOD, null)
            ServiceActionRoute.StopService -> CallForegroundService.stop(context)
            ServiceActionRoute.Ignore -> Unit
        }
    }

    companion object {
        const val ACTION_HANG_UP = "im.zuno.chat.HANG_UP_CALL"
        const val HANG_UP_METHOD = "hangUpCall"
    }
}
