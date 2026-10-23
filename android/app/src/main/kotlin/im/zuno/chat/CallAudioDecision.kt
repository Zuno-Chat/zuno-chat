package im.zuno.chat

import android.media.AudioManager

enum class CallTone {
    Ringback,
    Waiting,
}

enum class ToneAction {
    Start,
    Restart,
    Stop,
    None,
}

enum class ScoAction {
    Start,
    Stop,
    None,
}

object CallAudioDecision {
    fun wantedTone(wanted: Set<CallTone>): CallTone? = when {
        CallTone.Waiting in wanted -> CallTone.Waiting
        CallTone.Ringback in wanted -> CallTone.Ringback
        else -> null
    }

    fun tone(
        wanted: CallTone?,
        active: Boolean,
        routeSettled: Boolean,
        playing: CallTone?,
    ): ToneAction = when {
        wanted == null || !active -> if (playing != null) ToneAction.Stop else ToneAction.None
        playing == wanted -> ToneAction.None
        !routeSettled -> if (playing != null) ToneAction.Stop else ToneAction.None
        playing == null -> ToneAction.Start
        else -> ToneAction.Restart
    }

    fun routeSettled(awaitedDevice: Int?, activeDevice: Int?): Boolean =
        awaitedDevice == null || awaitedDevice == activeDevice

    fun reportsChange(
        route: CallAudioRoute,
        headsets: Set<CallAudioRoute>,
        reportedRoute: CallAudioRoute?,
        reportedHeadsets: Set<CallAudioRoute>,
    ): Boolean = route != reportedRoute || headsets != reportedHeadsets

    fun scoAction(wantBluetooth: Boolean, scoRequested: Boolean): ScoAction = when {
        wantBluetooth == scoRequested -> ScoAction.None
        wantBluetooth -> ScoAction.Start
        else -> ScoAction.Stop
    }

    fun focusGranted(result: Int): Boolean = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED ||
        result == AudioManager.AUDIOFOCUS_REQUEST_DELAYED
}
