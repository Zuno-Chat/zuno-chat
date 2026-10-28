package im.zuno.chat.zuno_notifications

import android.content.Context
import android.util.Log

object InstantRing {
    private const val TAG = "InstantRing"

    fun present(
        context: Context,
        call: InstantRingCall,
        appInFront: Boolean,
        userId: String?,
        callActive: Boolean,
        ringMs: Long,
        tonePath: (String) -> String?,
    ): Boolean {
        val app = context.applicationContext
        return try {
            val prefs = FlutterStore.preferences(app)
            val nowMs = System.currentTimeMillis()
            val state = InstantRingState(
                appInFront = appInFront,
                userId = userId,
                resolved = RingDecisions.resolvedCallIds(prefs.all, nowMs),
                showingCallId = IncomingRing.showingCallId(app),
                rememberedCallId = IncomingRing.rememberedCallId(app, nowMs),
                callActive = callActive,
                room = PushNoticeDecision.parseRoomCache(
                    prefs.getString(FlutterStore.ROOM_CACHE, null),
                )[call.roomId],
                preview = prefs.getString(FlutterStore.NOTIFICATION_PREVIEW, null),
                ringtone = prefs.getBoolean(FlutterStore.RINGTONE, true),
                vibrate = prefs.getBoolean(FlutterStore.CALL_VIBRATION, true),
            )
            val outcome = InstantRingDecision.decide(call, state) {
                IncomingCallStyle.canRing(app, it)
            }
            when (outcome) {
                is InstantRingOutcome.Skip -> {
                    Log.d(TAG, "Not ringing at once: ${outcome.reason}")
                    false
                }

                is InstantRingOutcome.Present -> {
                    val spec = specFor(app, call, outcome.look, ringMs)
                    IncomingCallStyle.show(app, spec, tonePath).also { shown ->
                        if (shown) IncomingRing.remember(app, call, nowMs)
                        Log.d(TAG, if (shown) "Ringing at once" else "Ring could not show")
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not ring at once", e)
            false
        }
    }

    private fun specFor(
        app: Context,
        call: InstantRingCall,
        look: InstantRingLook,
        ringMs: Long,
    ): IncomingCallSpec {
        val kind = app.getString(
            if (call.isVideo) R.string.callsIncomingVideo else R.string.callsIncomingVoice,
        )
        return IncomingCallSpec(
            channelId = look.channelId,
            name = when (val name = look.name) {
                is RingName.Named -> name.name
                RingName.Generic -> app.getString(R.string.callsGenericRingName)
            },
            text = when (val text = look.text) {
                is RingText.Caller -> text.name
                RingText.Kind -> kind
            },
            callerId = call.callerId,
            isVideo = call.isVideo,
            roomId = call.roomId,
            callId = call.callId,
            avatarBytes = null,
            plan = look.plan,
            ringMs = ringMs,
        )
    }
}
