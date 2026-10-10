package im.zuno.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import im.zuno.chat.zuno_notifications.PushKind
import im.zuno.chat.zuno_notifications.PushNotice
import io.flutter.FlutterInjector

class PushNoticeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val receivedAtMs = System.currentTimeMillis()
        val receivedAtElapsedMs = SystemClock.elapsedRealtime()
        val app = context.applicationContext
        val appInFront = PushNotice.appInFront(app)
        val messageId = FcmPushKeys.messageId(intent.getStringExtra(MESSAGE_ID))
        val roomId = intent.getStringExtra(ROOM_ID)
        val eventId = intent.getStringExtra(EVENT_ID)
        val plan = filter.planFor(
            intent.getStringExtra(MESSAGE_TYPE),
            messageId,
            PushKind.of(eventId, roomId),
            appInFront,
        )
        if (plan == null) {
            Log.d(TAG, "Not a new push, nothing to do")
            return
        }
        val noticePosted = when (plan) {
            FcmReceivePlan.TestNotice -> PushNotice.postTest(app)

            is FcmReceivePlan.MessageNotice -> {
                plan.wakeLockKey?.let { PushWakeLock.hold(app, it) }
                if (plan.warmUpFlutter) warmUpFlutter(app)
                PushNotice.post(app, roomId, eventId, appInFront)
            }

            FcmReceivePlan.RecordOnly -> false
        }
        PushDeliveryLog.received(
            app,
            messageId,
            intent.extras,
            receivedAtMs,
            receivedAtElapsedMs,
            noticePosted = noticePosted,
        )
    }

    private fun warmUpFlutter(context: Context) {
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) loader.startInitialization(context)
        } catch (e: Exception) {
            CaughtErrors.record(context, "push flutter warm-up", e)
        }
    }

    private companion object {
        const val TAG = "PushNoticeReceiver"
        const val MESSAGE_ID = "google.message_id"
        const val MESSAGE_TYPE = "message_type"
        const val ROOM_ID = "room_id"
        const val EVENT_ID = "event_id"
        val filter = FcmReceiveFilter()
    }
}
