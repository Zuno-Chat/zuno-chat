package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PictureInPictureDecisionTest {
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
        assertFalse(
            PictureInPictureDecision.shouldHide(eligible = false, inPictureInPicture = false),
        )
    }

    @Test
    fun `a visible window keeps the camera`() {
        assertTrue(PictureInPictureDecision.keepsCamera(inPictureInPicture = true, started = true))
    }

    @Test
    fun `a window hidden by a locked screen does not`() {
        assertFalse(
            PictureInPictureDecision.keepsCamera(inPictureInPicture = true, started = false),
        )
    }

    @Test
    fun `the full screen leaves the camera to the app state`() {
        assertFalse(
            PictureInPictureDecision.keepsCamera(inPictureInPicture = false, started = true),
        )
    }

    @Test
    fun `Back from the first screen opens the window while it can show the other camera`() {
        assertEquals(
            RootBack.EnterPictureInPicture,
            PictureInPictureDecision.onRootBack(eligible = true, callHeld = true),
        )
    }

    @Test
    fun `Back from the first screen sends any other call to the background, never closing it`() {
        assertEquals(
            RootBack.MoveToBack,
            PictureInPictureDecision.onRootBack(eligible = false, callHeld = true),
        )
    }

    @Test
    fun `without a call Back from the first screen keeps the platform default`() {
        assertEquals(
            RootBack.Default,
            PictureInPictureDecision.onRootBack(eligible = false, callHeld = false),
        )
    }

    @Test
    fun `Back is kept from the system only while the window can open`() {
        assertTrue(PictureInPictureDecision.claimsBack(frameworkHandlesBack = false, eligible = true))
        assertFalse(
            PictureInPictureDecision.claimsBack(frameworkHandlesBack = false, eligible = false),
        )
        assertTrue(PictureInPictureDecision.claimsBack(frameworkHandlesBack = true, eligible = false))
    }
}
