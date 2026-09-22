package im.zuno.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import im.zuno.chat.zuno_notifications.PushNotice

class PushNoticeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PushNotice.post(
            context.applicationContext,
            intent.getStringExtra("room_id"),
            intent.getStringExtra("event_id"),
        )
    }
}
