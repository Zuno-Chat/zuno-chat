package im.zuno.chat

import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallAudioDecisionTest {
    @Test
    fun `a tone starts once it is wanted, call audio runs and the call's route is in place`() {
        assertEquals(
            ToneAction.Start,
            CallAudioDecision.tone(
                wanted = CallTone.Ringback,
                active = true,
                routeSettled = true,
                playing = null,
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
                routeSettled = true,
                playing = null,
            ),
        )
    }

    @Test
    fun `a tone waits for the call's route to switch, so a speaker call never rings in the earpiece`() {
        assertEquals(
            ToneAction.None,
            CallAudioDecision.tone(
                wanted = CallTone.Ringback,
                active = true,
                routeSettled = false,
                playing = null,
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
                routeSettled = true,
                playing = CallTone.Ringback,
            ),
        )
        assertEquals(
            ToneAction.Stop,
            CallAudioDecision.tone(
                wanted = CallTone.Ringback,
                active = false,
                routeSettled = true,
                playing = CallTone.Ringback,
            ),
        )
    }

    @Test
    fun `a playing tone keeps playing through a route change, since it follows the call's route`() {
        assertEquals(
            ToneAction.None,
            CallAudioDecision.tone(
                wanted = CallTone.Ringback,
                active = true,
                routeSettled = false,
                playing = CallTone.Ringback,
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
                routeSettled = true,
                playing = CallTone.Ringback,
            ),
        )
    }

    @Test
    fun `a different tone wanted mid route switch stops the old one and waits for the route`() {
        assertEquals(
            ToneAction.Stop,
            CallAudioDecision.tone(
                wanted = CallTone.Waiting,
                active = true,
                routeSettled = false,
                playing = CallTone.Ringback,
            ),
        )
    }

    @Test
    fun `the route is in place once the awaited device is active, or nothing is awaited`() {
        assertTrue(CallAudioDecision.routeSettled(awaitedDevice = 2, activeDevice = 2))
        assertTrue(CallAudioDecision.routeSettled(awaitedDevice = null, activeDevice = 1))
        assertTrue(CallAudioDecision.routeSettled(awaitedDevice = null, activeDevice = null))
    }

    @Test
    fun `the route is not in place while the platform still plays on another device`() {
        assertFalse(CallAudioDecision.routeSettled(awaitedDevice = 2, activeDevice = 1))
        assertFalse(CallAudioDecision.routeSettled(awaitedDevice = 2, activeDevice = null))
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
