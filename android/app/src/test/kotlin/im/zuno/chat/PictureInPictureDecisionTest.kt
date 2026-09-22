package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PictureInPictureDecisionTest {
    @Test
    fun `no picture-in-picture at all before Android 8`() {
        assertEquals(PipEntryMode.Unsupported, PictureInPictureDecision.entryMode(sdkInt = 25))
    }

    @Test
    fun `enters from the user-leave hint on Android 8 through 11`() {
        assertEquals(PipEntryMode.EnterOnLeave, PictureInPictureDecision.entryMode(sdkInt = 26))
        assertEquals(PipEntryMode.EnterOnLeave, PictureInPictureDecision.entryMode(sdkInt = 30))
    }

    @Test
    fun `lets the system auto-enter from Android 12 on`() {
        assertEquals(PipEntryMode.AutoEnter, PictureInPictureDecision.entryMode(sdkInt = 31))
    }

    @Test
    fun `hides the window when it is showing and no remote video is left`() {
        assertTrue(PictureInPictureDecision.shouldHide(eligible = false, inPictureInPicture = true))
    }

    @Test
    fun `keeps the window while a remote video is still on`() {
        assertFalse(PictureInPictureDecision.shouldHide(eligible = true, inPictureInPicture = true))
    }

    @Test
    fun `nothing to hide when not in the window`() {
        assertFalse(PictureInPictureDecision.shouldHide(eligible = false, inPictureInPicture = false))
    }

    @Test
    fun `leaving the window while resumed means the user expanded it`() {
        assertEquals(
            PipExit.Expanded,
            PictureInPictureDecision.onLeft(lifecycleCreated = false, selfHidden = false),
        )
    }

    @Test
    fun `leaving the window while stopped means the user closed it`() {
        assertEquals(
            PipExit.ClosedByUser,
            PictureInPictureDecision.onLeft(lifecycleCreated = true, selfHidden = false),
        )
    }

    @Test
    fun `leaving the window because the app hid it is not a user close`() {
        assertEquals(
            PipExit.Hidden,
            PictureInPictureDecision.onLeft(lifecycleCreated = true, selfHidden = true),
        )
    }
}
