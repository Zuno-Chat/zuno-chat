package im.zuno.chat

import android.os.Build

enum class PipEntryMode {
    EnterOnLeave,
    AutoEnter,
}

enum class PipExit {
    Expanded,
    Hidden,
    ClosedByUser,
}

object PictureInPictureDecision {
    fun entryMode(sdkInt: Int): PipEntryMode = if (sdkInt < Build.VERSION_CODES.S) {
        PipEntryMode.EnterOnLeave
    } else {
        PipEntryMode.AutoEnter
    }

    fun shouldHide(eligible: Boolean, inPictureInPicture: Boolean): Boolean =
        inPictureInPicture && !eligible

    fun onLeft(lifecycleCreated: Boolean, selfHidden: Boolean): PipExit = when {
        selfHidden -> PipExit.Hidden
        lifecycleCreated -> PipExit.ClosedByUser
        else -> PipExit.Expanded
    }
}
