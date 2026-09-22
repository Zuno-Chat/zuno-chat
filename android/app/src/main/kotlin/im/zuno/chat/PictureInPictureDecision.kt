package im.zuno.chat

import android.os.Build

enum class PipEntryMode {
    Unsupported,
    EnterOnLeave,
    AutoEnter,
}

enum class PipExit {
    Expanded,
    Hidden,
    ClosedByUser,
}

object PictureInPictureDecision {
    fun entryMode(sdkInt: Int): PipEntryMode = when {
        sdkInt < Build.VERSION_CODES.O -> PipEntryMode.Unsupported
        sdkInt < Build.VERSION_CODES.S -> PipEntryMode.EnterOnLeave
        else -> PipEntryMode.AutoEnter
    }

    fun shouldHide(eligible: Boolean, inPictureInPicture: Boolean): Boolean =
        inPictureInPicture && !eligible

    fun onLeft(lifecycleCreated: Boolean, selfHidden: Boolean): PipExit = when {
        selfHidden -> PipExit.Hidden
        lifecycleCreated -> PipExit.ClosedByUser
        else -> PipExit.Expanded
    }
}
