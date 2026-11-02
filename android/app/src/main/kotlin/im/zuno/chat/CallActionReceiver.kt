package im.zuno.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = route(context, intent.action)

    companion object {
        const val ACTION_HANG_UP = "im.zuno.chat.HANG_UP_CALL"
        private const val HANG_UP_METHOD = "hangUpCall"

        fun requestHangUp(context: Context) = route(context, ACTION_HANG_UP)

        private fun route(context: Context, action: String?) {
            val channel = AppEngine.callsChannel
            when (ServiceActionDecision.route(action, ACTION_HANG_UP, channel != null)) {
                ServiceActionRoute.DeliverToDart -> channel?.invokeMethod(HANG_UP_METHOD, null)
                ServiceActionRoute.StopService -> CallForegroundService.stop(context)
                ServiceActionRoute.Ignore -> Unit
            }
        }
    }
}
