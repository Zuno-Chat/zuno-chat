package im.zuno.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class LiveLocationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (
            ServiceActionDecision.route(
                intent.action,
                ACTION_STOP,
                LiveLocationChannel.attached,
            )
        ) {
            ServiceActionRoute.DeliverToDart -> LiveLocationChannel.requestStop()
            ServiceActionRoute.StopService -> LiveLocationService.stop(context)
            ServiceActionRoute.Ignore -> Unit
        }
    }

    companion object {
        const val ACTION_STOP = "im.zuno.chat.STOP_LIVE_LOCATION"
    }
}
