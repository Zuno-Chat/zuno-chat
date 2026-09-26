package im.zuno.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import im.zuno.chat.zuno_notifications.PushNotice
import im.zuno.chat.zuno_notifications.PushWakeLock

class PushNoticeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val appInFront = PushNotice.appInFront(app)
        if (!appInFront) PushWakeLock.acquire(app)
        PushDeliveryLog.record(app, intent.extras)
        PushNotice.post(
            app,
            intent.getStringExtra("room_id"),
            intent.getStringExtra("event_id"),
            appInFront,
        )
    }
}
