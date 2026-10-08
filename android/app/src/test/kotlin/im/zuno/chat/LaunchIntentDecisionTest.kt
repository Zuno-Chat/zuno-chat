package im.zuno.chat

import android.content.Intent
import org.junit.Assert.assertEquals
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

    @Test
    fun `a second copy opened from the launcher closes, leaving the running app as it was`() {
        assertEquals(
            DuplicateLaunch.Close,
            LaunchIntentDecision.onDuplicate(
                action = Intent.ACTION_MAIN,
                intentFlags = Intent.FLAG_ACTIVITY_NEW_TASK,
                handedOver = false,
                sameTask = true,
            ),
        )
    }

    @Test
    fun `a second copy opened by a notification hands its target to the running app`() {
        assertEquals(
            DuplicateLaunch.HandOver,
            LaunchIntentDecision.onDuplicate(
                action = "SELECT_NOTIFICATION",
                intentFlags = Intent.FLAG_ACTIVITY_NEW_TASK,
                handedOver = false,
                sameTask = true,
            ),
        )
    }

    @Test
    fun `a target is handed over once, never back and forth`() {
        assertEquals(
            DuplicateLaunch.Close,
            LaunchIntentDecision.onDuplicate(
                action = "SELECT_NOTIFICATION",
                intentFlags = Intent.FLAG_ACTIVITY_NEW_TASK,
                handedOver = true,
                sameTask = true,
            ),
        )
    }

    @Test
    fun `a relaunch from recents is never handed over`() {
        assertEquals(
            DuplicateLaunch.Close,
            LaunchIntentDecision.onDuplicate(
                action = "SELECT_NOTIFICATION",
                intentFlags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY,
                handedOver = false,
                sameTask = true,
            ),
        )
    }

    @Test
    fun `a second copy with nothing to open closes`() {
        assertEquals(
            DuplicateLaunch.Close,
            LaunchIntentDecision.onDuplicate(
                action = null,
                intentFlags = Intent.FLAG_ACTIVITY_NEW_TASK,
                handedOver = false,
                sameTask = true,
            ),
        )
    }

    @Test
    fun `a second copy opened inside another app brings the running app forward`() {
        assertEquals(
            DuplicateLaunch.HandOver,
            LaunchIntentDecision.onDuplicate(
                action = Intent.ACTION_MAIN,
                intentFlags = 0,
                handedOver = false,
                sameTask = false,
            ),
        )
    }
}
