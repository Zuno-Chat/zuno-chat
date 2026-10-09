package im.zuno.chat

import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallAudioDecisionTest {
    @Test
    fun `ringback starts once it is wanted and call audio runs`() {
        assertEquals(
            RingbackAction.Start,
            CallAudioDecision.ringback(
                wanted = true,
                active = true,
                playing = false,
                routeChanged = false,
            ),
        )
    }

    @Test
    fun `ringback waits for call audio, so it never starts on the wrong speaker`() {
        assertEquals(
            RingbackAction.None,
            CallAudioDecision.ringback(
                wanted = true,
                active = false,
                playing = false,
                routeChanged = false,
            ),
        )
    }

    @Test
    fun `a playing ringback stops once it is no longer wanted or call audio ends`() {
        assertEquals(
            RingbackAction.Stop,
            CallAudioDecision.ringback(
                wanted = false,
                active = true,
                playing = true,
                routeChanged = false,
            ),
        )
        assertEquals(
            RingbackAction.Stop,
            CallAudioDecision.ringback(
                wanted = true,
                active = false,
                playing = true,
                routeChanged = false,
            ),
        )
    }

    @Test
    fun `a playing ringback is left alone while its route stays put`() {
        assertEquals(
            RingbackAction.None,
            CallAudioDecision.ringback(
                wanted = true,
                active = true,
                playing = true,
                routeChanged = false,
            ),
        )
    }

    @Test
    fun `a route change restarts a playing ringback on the new route`() {
        assertEquals(
            RingbackAction.Restart,
            CallAudioDecision.ringback(
                wanted = true,
                active = true,
                playing = true,
                routeChanged = true,
            ),
        )
    }

    @Test
    fun `a route change retries a wanted ringback that failed to start`() {
        assertEquals(
            RingbackAction.Start,
            CallAudioDecision.ringback(
                wanted = true,
                active = true,
                playing = false,
                routeChanged = true,
            ),
        )
    }

    @Test
    fun `a route change never starts a ringback nobody wants`() {
        assertEquals(
            RingbackAction.None,
            CallAudioDecision.ringback(
                wanted = false,
                active = true,
                playing = false,
                routeChanged = true,
            ),
        )
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
