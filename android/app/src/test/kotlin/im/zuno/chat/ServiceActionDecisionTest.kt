package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class ServiceActionDecisionTest {
    @Test
    fun `delivers a call hang up to dart while the app engine is alive`() {
        assertEquals(
            ServiceActionRoute.DeliverToDart,
            ServiceActionDecision.route(
                action = CallActionReceiver.ACTION_HANG_UP,
                expected = CallActionReceiver.ACTION_HANG_UP,
                dartAttached = true,
            ),
        )
    }

    @Test
    fun `stops the call service when no engine is left to hang the call up`() {
        assertEquals(
            ServiceActionRoute.StopService,
            ServiceActionDecision.route(
                action = CallActionReceiver.ACTION_HANG_UP,
                expected = CallActionReceiver.ACTION_HANG_UP,
                dartAttached = false,
            ),
        )
    }

    @Test
    fun `hands a live location stop to dart so it clears the share`() {
        assertEquals(
            ServiceActionRoute.DeliverToDart,
            ServiceActionDecision.route(
                action = LiveLocationActionReceiver.ACTION_STOP,
                expected = LiveLocationActionReceiver.ACTION_STOP,
                dartAttached = true,
            ),
        )
    }

    @Test
    fun `stops live location capture itself when dart is gone`() {
        assertEquals(
            ServiceActionRoute.StopService,
            ServiceActionDecision.route(
                action = LiveLocationActionReceiver.ACTION_STOP,
                expected = LiveLocationActionReceiver.ACTION_STOP,
                dartAttached = false,
            ),
        )
    }

    @Test
    fun `ignores an action meant for another receiver`() {
        assertEquals(
            ServiceActionRoute.Ignore,
            ServiceActionDecision.route(
                action = CallActionReceiver.ACTION_HANG_UP,
                expected = LiveLocationActionReceiver.ACTION_STOP,
                dartAttached = true,
            ),
        )
    }

    @Test
    fun `ignores an intent with no action at all`() {
        assertEquals(
            ServiceActionRoute.Ignore,
            ServiceActionDecision.route(
                action = null,
                expected = CallActionReceiver.ACTION_HANG_UP,
                dartAttached = true,
            ),
        )
    }
}
