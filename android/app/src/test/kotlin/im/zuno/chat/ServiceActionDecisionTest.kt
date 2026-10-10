package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class ServiceActionDecisionTest {
    private val actions =
        listOf(CallActionReceiver.ACTION_HANG_UP, LiveLocationActionReceiver.ACTION_STOP)

    @Test
    fun `a call hang up or a live location stop goes to dart while the app engine is alive`() {
        for (action in actions) {
            assertEquals(
                action,
                ServiceActionRoute.DeliverToDart,
                ServiceActionDecision.route(
                    action = action,
                    expected = action,
                    dartAttached = true,
                ),
            )
        }
    }

    @Test
    fun `with no engine left the service stops the call or the live location capture itself`() {
        for (action in actions) {
            assertEquals(
                action,
                ServiceActionRoute.StopService,
                ServiceActionDecision.route(
                    action = action,
                    expected = action,
                    dartAttached = false,
                ),
            )
        }
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
