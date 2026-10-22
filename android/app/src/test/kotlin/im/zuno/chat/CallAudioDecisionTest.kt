package im.zuno.chat

import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallAudioDecisionTest {
    @Test
    fun `a tone starts once it is wanted and call audio runs`() {
        assertEquals(
            ToneAction.Start,
            CallAudioDecision.tone(
                wanted = CallTone.Ringback,
                active = true,
                playing = null,
                routeChanged = false,
            ),
        )
    }

    @Test
    fun `a tone waits for call audio, so it never starts on the wrong speaker`() {
        assertEquals(
            ToneAction.None,
            CallAudioDecision.tone(
                wanted = CallTone.Waiting,
                active = false,
                playing = null,
                routeChanged = false,
            ),
        )
    }

    @Test
    fun `a playing tone stops once it is no longer wanted or call audio ends`() {
        assertEquals(
            ToneAction.Stop,
            CallAudioDecision.tone(
                wanted = null,
                active = true,
                playing = CallTone.Ringback,
                routeChanged = false,
            ),
        )
        assertEquals(
            ToneAction.Stop,
            CallAudioDecision.tone(
                wanted = CallTone.Ringback,
                active = false,
                playing = CallTone.Ringback,
                routeChanged = false,
            ),
        )
    }

    @Test
    fun `a playing tone is left alone while its route stays put`() {
        assertEquals(
            ToneAction.None,
            CallAudioDecision.tone(
                wanted = CallTone.Waiting,
                active = true,
                playing = CallTone.Waiting,
                routeChanged = false,
            ),
        )
    }

    @Test
    fun `a route change restarts a playing tone on the new route`() {
        assertEquals(
            ToneAction.Restart,
            CallAudioDecision.tone(
                wanted = CallTone.Ringback,
                active = true,
                playing = CallTone.Ringback,
                routeChanged = true,
            ),
        )
    }

    @Test
    fun `a route change retries a wanted tone that failed to start`() {
        assertEquals(
            ToneAction.Start,
            CallAudioDecision.tone(
                wanted = CallTone.Ringback,
                active = true,
                playing = null,
                routeChanged = true,
            ),
        )
    }

    @Test
    fun `a route change never starts a tone nobody wants`() {
        assertEquals(
            ToneAction.None,
            CallAudioDecision.tone(
                wanted = null,
                active = true,
                playing = null,
                routeChanged = true,
            ),
        )
    }

    @Test
    fun `a different tone wanted replaces the one playing`() {
        assertEquals(
            ToneAction.Restart,
            CallAudioDecision.tone(
                wanted = CallTone.Waiting,
                active = true,
                playing = CallTone.Ringback,
                routeChanged = false,
            ),
        )
    }

    @Test
    fun `the waiting tone wins over ringback, so the two never play at once`() {
        assertEquals(
            CallTone.Waiting,
            CallAudioDecision.wantedTone(setOf(CallTone.Ringback, CallTone.Waiting)),
        )
        assertEquals(CallTone.Ringback, CallAudioDecision.wantedTone(setOf(CallTone.Ringback)))
        assertEquals(null, CallAudioDecision.wantedTone(emptySet()))
    }

    @Test
    fun `a change is reported when the connected headsets differ from the last report`() {
        assertTrue(
            CallAudioDecision.reportsChange(
                route = CallAudioRoute.Earpiece,
                headsets = setOf(CallAudioRoute.WiredHeadset),
                reportedRoute = CallAudioRoute.Earpiece,
                reportedHeadsets = emptySet(),
            ),
        )
        assertTrue(
            CallAudioDecision.reportsChange(
                route = CallAudioRoute.Earpiece,
                headsets = emptySet(),
                reportedRoute = CallAudioRoute.Earpiece,
                reportedHeadsets = setOf(CallAudioRoute.Bluetooth),
            ),
        )
    }

    @Test
    fun `a change is reported when the route heard differs, as when a bluetooth link drops`() {
        assertTrue(
            CallAudioDecision.reportsChange(
                route = CallAudioRoute.Earpiece,
                headsets = setOf(CallAudioRoute.Bluetooth),
                reportedRoute = CallAudioRoute.Bluetooth,
                reportedHeadsets = setOf(CallAudioRoute.Bluetooth),
            ),
        )
    }

    @Test
    fun `nothing is reported while the route and headsets match the last report`() {
        assertFalse(
            CallAudioDecision.reportsChange(
                route = CallAudioRoute.Bluetooth,
                headsets = setOf(CallAudioRoute.Bluetooth, CallAudioRoute.WiredHeadset),
                reportedRoute = CallAudioRoute.Bluetooth,
                reportedHeadsets = setOf(CallAudioRoute.WiredHeadset, CallAudioRoute.Bluetooth),
            ),
        )
    }

    @Test
    fun `bluetooth opens SCO when this call has not asked for it yet`() {
        assertEquals(
            ScoAction.Start,
            CallAudioDecision.scoAction(wantBluetooth = true, scoRequested = false),
        )
    }

    @Test
    fun `bluetooth applied again never opens SCO a second time`() {
        assertEquals(
            ScoAction.None,
            CallAudioDecision.scoAction(wantBluetooth = true, scoRequested = true),
        )
    }

    @Test
    fun `leaving bluetooth closes the SCO this call asked for`() {
        assertEquals(
            ScoAction.Stop,
            CallAudioDecision.scoAction(wantBluetooth = false, scoRequested = true),
        )
    }

    @Test
    fun `a call that never asked for SCO never closes it`() {
        assertEquals(
            ScoAction.None,
            CallAudioDecision.scoAction(wantBluetooth = false, scoRequested = false),
        )
    }

    @Test
    fun `focus granted now or queued behind a phone call both count as held`() {
        assertTrue(CallAudioDecision.focusGranted(AudioManager.AUDIOFOCUS_REQUEST_GRANTED))
        assertTrue(CallAudioDecision.focusGranted(AudioManager.AUDIOFOCUS_REQUEST_DELAYED))
    }

    @Test
    fun `refused focus is not held`() {
        assertFalse(CallAudioDecision.focusGranted(AudioManager.AUDIOFOCUS_REQUEST_FAILED))
    }
}
