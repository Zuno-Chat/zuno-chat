package im.zuno.chat

import android.content.Intent

object LaunchIntentDecision {
    fun carriesLaunchTarget(intentFlags: Int, restoringState: Boolean): Boolean =
        !restoringState && (intentFlags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0
}
