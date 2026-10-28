package im.zuno.chat.zuno_notifications

import android.app.NotificationManager
import org.json.JSONException
import org.json.JSONObject

class RingPlan(
    val ringtoneAsset: String?,
    val vibrationPattern: LongArray?,
    val waitingText: String?,
) {
    val waiting: Boolean get() = waitingText != null

    val toneNow: String? get() = if (waiting) null else ringtoneAsset

    fun quiet(): RingPlan = RingPlan(null, vibrationPattern, waitingText)

    companion object {
        private const val RINGTONE_ASSET = "assets/sounds/ringtone.wav"
        private val callVibration = longArrayOf(0, 800, 500, 800, 2000)

        fun from(args: Map<String, Any?>): RingPlan = of(
            ringtone = args["ringtone"] == true,
            vibrate = args["vibrate"] == true,
            waitingText = args["waitingText"] as? String,
        )

        fun of(ringtone: Boolean, vibrate: Boolean, waitingText: String? = null): RingPlan =
            RingPlan(
                ringtoneAsset = RINGTONE_ASSET.takeIf { ringtone },
                vibrationPattern = callVibration.copyOf().takeIf { vibrate },
                waitingText = waitingText,
            )
    }
}

data class RememberedRing(val callId: String, val postedAtMs: Long) {
    companion object {
        fun record(call: InstantRingCall, postedAtMs: Long): String = JSONObject().apply {
            put("roomId", call.roomId)
            put("callId", call.callId)
            put("callerId", call.callerId)
            put("isVideo", call.isVideo)
            put("postedAt", postedAtMs)
        }.toString()

        fun parse(stored: String?): RememberedRing? {
            val record = try {
                JSONObject(stored ?: return null)
            } catch (e: JSONException) {
                return null
            }
            return of(record.opt("roomId"), record.opt("callId"), record.opt("postedAt"))
        }

        fun of(roomId: Any?, callId: Any?, postedAt: Any?): RememberedRing? {
            if (roomId !is String || callId !is String) return null
            val postedAtMs = when (postedAt) {
                is Int -> postedAt.toLong()
                is Long -> postedAt
                else -> return null
            }
            return RememberedRing(callId, postedAtMs)
        }
    }
}

data class RingCancel(val forget: Boolean, val dismiss: Boolean)

object RingDecisions {
    const val RING_TIMEOUT_MS = 60_000L
    const val SELECT_FOREGROUND_ACTION = "SELECT_FOREGROUND_NOTIFICATION"
    const val SELECT_ACTION = "SELECT_NOTIFICATION"
    const val ANSWER_ACTION_ID = "accept"
    const val DECLINE_ACTION_ID = "decline"
    const val NOTIFICATION_ID_EXTRA = "notificationId"
    const val ACTION_ID_EXTRA = "actionId"
    const val TOKEN_EXTRA = "im.zuno.chat.zuno_notifications.RING_TOKEN"
    private const val REMEMBERED_RING_MAX_AGE_MS = 45_000L
    private const val RESOLVED_RETENTION_MS = 300_000L

    fun ringLaunch(action: String?, notificationId: Int): Boolean =
        action == SELECT_FOREGROUND_ACTION && notificationId == IncomingRing.NOTIFICATION_ID

    fun answered(action: String?, notificationId: Int, actionId: String?): Boolean =
        ringLaunch(action, notificationId) && actionId == ANSWER_ACTION_ID

    fun claimsRing(action: String?, notificationId: Int, actionId: String?): Boolean {
        val notificationLaunch = action == SELECT_FOREGROUND_ACTION || action == SELECT_ACTION
        val ringTarget = notificationId == IncomingRing.NOTIFICATION_ID ||
            actionId == ANSWER_ACTION_ID ||
            actionId == DECLINE_ACTION_ID
        return notificationLaunch && ringTarget
    }

    fun tokenMatches(presented: String?, ringToken: String?): Boolean =
        ringToken != null && presented == ringToken

    fun cancel(
        requestedCallId: String?,
        ringingCallId: String?,
        remembered: RememberedRing?,
        nowMs: Long,
    ): RingCancel {
        if (requestedCallId == null) return RingCancel(forget = true, dismiss = true)
        val forget = !remembersAnotherCall(remembered, requestedCallId, nowMs)
        val dismiss = if (ringingCallId == null) forget else ringingCallId == requestedCallId
        return RingCancel(forget, dismiss)
    }

    fun resolvedCallIds(stored: Map<String, *>, nowMs: Long): Set<String> = stored.mapNotNullTo(
        HashSet(),
    ) { (key, at) ->
        key.removePrefix(FlutterStore.RESOLVED_CALL_PREFIX).takeIf {
            key.startsWith(FlutterStore.RESOLVED_CALL_PREFIX) &&
                at is Long &&
                nowMs - at <= RESOLVED_RETENTION_MS
        }
    }

    fun canRing(
        notificationsEnabled: Boolean,
        channelImportance: Int?,
        groupBlocked: Boolean,
    ): Boolean = notificationsEnabled &&
        channelImportance != null &&
        channelImportance != NotificationManager.IMPORTANCE_NONE &&
        !groupBlocked

    fun ringsAloud(channelImportance: Int?): Boolean =
        channelImportance != null && channelImportance >= NotificationManager.IMPORTANCE_DEFAULT

    fun remembersRing(remembered: RememberedRing?, nowMs: Long): String? =
        remembered?.takeIf { nowMs - it.postedAtMs <= REMEMBERED_RING_MAX_AGE_MS }?.callId

    fun showingRing(notificationShowing: Boolean, remembered: RememberedRing?): String? =
        remembered?.callId?.takeIf { notificationShowing }

    fun stops(ringingCallId: String?, requestedCallId: String?): Boolean =
        ringingCallId == null || requestedCallId == null || ringingCallId == requestedCallId

    private fun remembersAnotherCall(
        remembered: RememberedRing?,
        callId: String,
        nowMs: Long,
    ): Boolean = remembersRing(remembered, nowMs).let { it != null && it != callId }
}
