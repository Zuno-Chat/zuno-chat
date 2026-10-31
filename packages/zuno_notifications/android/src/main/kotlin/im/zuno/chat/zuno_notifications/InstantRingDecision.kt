package im.zuno.chat.zuno_notifications

data class InstantRingCall(
    val roomId: String,
    val callId: String,
    val callerId: String,
    val callerName: String,
    val roomName: String,
    val isVideo: Boolean,
)

data class InstantRingState(
    val appInFront: Boolean,
    val userId: String?,
    val resolved: Set<String>,
    val ring: RingNow,
    val callActive: Boolean,
    val room: CachedRoom?,
    val preview: String?,
    val ringtone: Boolean,
    val vibrate: Boolean,
)

sealed interface RingName {
    data class Named(val name: String) : RingName

    data object Generic : RingName
}

sealed interface RingText {
    data class Caller(val name: String) : RingText

    data object Kind : RingText
}

class InstantRingLook(
    val channelId: String,
    val name: RingName,
    val text: RingText,
    val plan: RingPlan,
)

sealed interface InstantRingOutcome {
    class Present(val look: InstantRingLook) : InstantRingOutcome

    data class Skip(val reason: String) : InstantRingOutcome
}

object InstantRingDecision {
    const val RING_CHANNEL = "calls_ringing"
    const val GROUP_RING_CHANNEL = "calls_ringing_group"

    fun unavailable(appInFront: Boolean, userId: String?): String? = when {
        appInFront -> "app_in_front"
        userId.isNullOrEmpty() -> "no_session"
        else -> null
    }

    fun decide(
        call: InstantRingCall,
        state: InstantRingState,
        canRing: (String) -> Boolean,
    ): InstantRingOutcome {
        val skip = unavailable(state.appInFront, state.userId) ?: when {
            call.callerId == state.userId -> "own_call"
            else -> when (RingDecisions.offer(call.callId, state.ring, state.resolved)) {
                RingOffer.RINGING -> "already_ringing"
                RingOffer.RANG_HERE -> "already_rung"
                RingOffer.BUSY -> "busy_ringing"
                RingOffer.PRESENT -> null
            }
        } ?: when {
            call.callId in state.resolved -> "resolved"
            state.callActive -> "busy_active"
            else -> null
        }
        if (skip != null) return InstantRingOutcome.Skip(skip)
        val look = lookFor(call, state)
        if (!canRing(look.channelId)) return InstantRingOutcome.Skip("cannot_show")
        return InstantRingOutcome.Present(look)
    }

    private fun lookFor(call: InstantRingCall, state: InstantRingState): InstantRingLook {
        val room = state.room
        val group = room?.isDirect != true
        val hidden = state.preview == FlutterStore.PREVIEW_HIDDEN
        val name = room?.name ?: call.roomName.ifBlank { call.callerName }
        return InstantRingLook(
            channelId = if (group) GROUP_RING_CHANNEL else RING_CHANNEL,
            name = if (hidden) RingName.Generic else RingName.Named(name.trim()),
            text = if (!hidden && group && call.callerName.isNotBlank()) {
                RingText.Caller(call.callerName.trim())
            } else {
                RingText.Kind
            },
            plan = RingPlan.of(ringtone = state.ringtone, vibrate = state.vibrate),
        )
    }
}
