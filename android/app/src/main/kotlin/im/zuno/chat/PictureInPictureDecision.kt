package im.zuno.chat

import android.os.Build

enum class PipEntryMode {
    EnterOnLeave,
    AutoEnter,
}

enum class RootBack {
    EnterPictureInPicture,
    MoveToBack,
    Default,
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

    fun claimsBack(frameworkHandlesBack: Boolean, eligible: Boolean): Boolean =
        frameworkHandlesBack || eligible

    fun onRootBack(eligible: Boolean, callHeld: Boolean): RootBack = when {
        eligible -> RootBack.EnterPictureInPicture
        callHeld -> RootBack.MoveToBack
        else -> RootBack.Default
    }
}
