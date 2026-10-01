package im.zuno.chat.zuno_call_style

class RingPlan(val ringtoneAsset: String?, val vibrationPattern: LongArray?) {
    companion object {
        fun from(args: Map<String, Any?>): RingPlan = RingPlan(
            ringtoneAsset = (args["ringtoneAsset"] as? String)
                ?.takeIf { args["ringtone"] == true && it.isNotBlank() },
            vibrationPattern = if (args["vibrate"] == true) {
                vibrationPattern(args["vibrationPattern"])
            } else {
                null
            },
        )

        private fun vibrationPattern(raw: Any?): LongArray? {
            val entries = raw as? List<*> ?: return null
            val timings = entries.map { (it as? Number)?.toLong() ?: return null }.toLongArray()
            if (timings.any { it < 0 } || timings.none { it > 0 }) return null
            return timings
        }
    }
}

data class RememberedRing(val callId: String, val postedAtMs: Long) {
    companion object {
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
    const val SELECT_NOTIFICATION_ACTION = "SELECT_FOREGROUND_NOTIFICATION"
    const val ANSWER_ACTION_ID = "accept"
    private const val REMEMBERED_RING_MAX_AGE_MS = 45_000L
    private const val FULL_STRENGTH = 255

    fun answered(action: String?, notificationId: Int, actionId: String?): Boolean =
        action == SELECT_NOTIFICATION_ACTION &&
            notificationId == IncomingRing.NOTIFICATION_ID &&
            actionId == ANSWER_ACTION_ID

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

    fun stops(ringingCallId: String?, requestedCallId: String?): Boolean =
        ringingCallId == null || requestedCallId == null || ringingCallId == requestedCallId

    fun amplitudes(pattern: LongArray): IntArray =
        IntArray(pattern.size) { if (it % 2 == 1) FULL_STRENGTH else 0 }

    private fun remembersAnotherCall(
        remembered: RememberedRing?,
        callId: String,
        nowMs: Long,
    ): Boolean = remembered != null &&
        remembered.callId != callId &&
        nowMs - remembered.postedAtMs <= REMEMBERED_RING_MAX_AGE_MS
}
