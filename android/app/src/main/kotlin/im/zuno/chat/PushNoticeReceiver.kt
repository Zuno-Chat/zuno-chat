package im.zuno.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import im.zuno.chat.zuno_notifications.IncomingRing
import im.zuno.chat.zuno_notifications.InstantRing
import im.zuno.chat.zuno_notifications.InstantRingCall
import im.zuno.chat.zuno_notifications.InstantRingDecision
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
        val ringData = listOf(RingBlob.PUSH_KEY, RingBlob.END_PUSH_KEY)
            .associateWith { intent.getStringExtra(it) }
        val plan = FcmReceiveFilter.shared.planFor(
            intent.getStringExtra(MESSAGE_TYPE),
            messageId,
            RingBlob.pushKind(eventId, roomId, ringData),
            appInFront,
            receivedAtElapsedMs,
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

            FcmReceivePlan.RingWarmUp -> {
                warmUpFlutter(app)
                ringAtOnce(app, messageId, ringData, appInFront)
            }

            FcmReceivePlan.RingEnd -> {
                endRing(app, ringData)
                false
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

    private fun ringAtOnce(
        context: Context,
        messageId: String?,
        ringData: Map<String, String?>,
        appInFront: Boolean,
    ): Boolean {
        val userId = RingRegistration.userId(context)
        InstantRingDecision.unavailable(appInFront, userId)?.let {
            Log.d(TAG, "Not ringing at once: $it")
            return false
        }
        val outcome = RingRegistration.judgeAndHandOff(context, messageId, ringData)
        if (outcome !is RingPushOutcome.Ring) return false
        val ring = outcome.ring
        return InstantRing.present(
            context,
            InstantRingCall(
                roomId = ring.room,
                callId = ring.call,
                callerId = ring.caller,
                callerName = ring.cname,
                roomName = ring.rname,
                isVideo = ring.kind == RingKind.VIDEO,
            ),
            appInFront = appInFront,
            userId = userId,
            callActive = KeptEngine.holds(EngineKeepReason.Call),
            ringMs = outcome.ringMs,
            tonePath = { flutterAssetKey(context, it) },
        )
    }

    private fun endRing(context: Context, ringData: Map<String, String?>) {
        val outcome = RingRegistration.judge(context, ringData)
        if (outcome !is RingPushOutcome.End) return
        IncomingRing.endFromServer(context, outcome.end.call, System.currentTimeMillis())
        Log.d(TAG, "Ring ended by the server")
    }

    private fun flutterAssetKey(context: Context, asset: String): String? = try {
        FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
    } catch (e: Exception) {
        CaughtErrors.record(context, "instant ring tone lookup", e)
        null
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
    }
}
