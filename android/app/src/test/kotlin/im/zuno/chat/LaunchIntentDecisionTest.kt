package im.zuno.chat

import android.content.Intent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LaunchIntentDecisionTest {
    @Test
    fun `a fresh launch carries its share or room`() {
        assertTrue(
            LaunchIntentDecision.carriesLaunchTarget(
                intentFlags = Intent.FLAG_ACTIVITY_NEW_TASK,
                restoringState = false,
            ),
        )
    }

    @Test
    fun `a relaunch from recents does not repeat it`() {
        assertFalse(
            LaunchIntentDecision.carriesLaunchTarget(
                intentFlags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY,
                restoringState = false,
            ),
        )
    }

    @Test
    fun `an activity restored after its process died does not repeat it`() {
        assertFalse(
            LaunchIntentDecision.carriesLaunchTarget(
                intentFlags = Intent.FLAG_ACTIVITY_NEW_TASK,
                restoringState = true,
            ),
        )
    }
}
