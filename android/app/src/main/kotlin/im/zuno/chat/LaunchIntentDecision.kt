package im.zuno.chat

import android.content.Intent

enum class DuplicateLaunch {
    Close,
    HandOver,
}

object LaunchIntentDecision {
    fun carriesLaunchTarget(intentFlags: Int, restoringState: Boolean): Boolean =
        !restoringState && (intentFlags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0

    fun onDuplicate(
        action: String?,
        intentFlags: Int,
        handedOver: Boolean,
        sameTask: Boolean,
    ): DuplicateLaunch = when {
        handedOver || !carriesLaunchTarget(intentFlags, restoringState = false) ->
            DuplicateLaunch.Close
        action != null && action != Intent.ACTION_MAIN -> DuplicateLaunch.HandOver
        sameTask -> DuplicateLaunch.Close
        else -> DuplicateLaunch.HandOver
    }
}
