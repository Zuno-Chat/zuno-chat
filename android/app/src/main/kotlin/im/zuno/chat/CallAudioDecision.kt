package im.zuno.chat

import android.media.AudioManager

enum class RingbackAction {
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
    fun ringback(
        wanted: Boolean,
        active: Boolean,
        playing: Boolean,
        routeChanged: Boolean,
    ): RingbackAction = when {
        !wanted || !active -> if (playing) RingbackAction.Stop else RingbackAction.None
        !playing -> RingbackAction.Start
        routeChanged -> RingbackAction.Restart
        else -> RingbackAction.None
    }

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
