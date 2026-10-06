package im.zuno.chat

import android.os.Build

enum class PipEntryMode {
    EnterOnLeave,
    AutoEnter,
}

object PictureInPictureDecision {
    fun entryMode(sdkInt: Int): PipEntryMode = if (sdkInt < Build.VERSION_CODES.S) {
        PipEntryMode.EnterOnLeave
    } else {
        PipEntryMode.AutoEnter
    }

    fun shouldHide(eligible: Boolean, inPictureInPicture: Boolean): Boolean =
        inPictureInPicture && !eligible

    fun keepsCamera(inPictureInPicture: Boolean, started: Boolean): Boolean =
        inPictureInPicture && started
}
