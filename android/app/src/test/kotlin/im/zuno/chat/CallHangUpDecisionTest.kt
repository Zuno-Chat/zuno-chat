package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class CallHangUpDecisionTest {
    @Test
    fun `delivers to dart while the app engine is alive`() {
        assertEquals(
            CallHangUpAction.DeliverToDart,
            CallHangUpDecision.decide(
                action = CallActionReceiver.ACTION_HANG_UP,
                appEngineAlive = true,
            ),
        )
    }

    @Test
    fun `stops the service when no engine is left to hang the call up`() {
        assertEquals(
            CallHangUpAction.StopService,
            CallHangUpDecision.decide(
                action = CallActionReceiver.ACTION_HANG_UP,
                appEngineAlive = false,
            ),
        )
    }

    @Test
    fun `ignores an unrelated action`() {
        assertEquals(
            CallHangUpAction.Ignore,
            CallHangUpDecision.decide(
                action = "android.intent.action.BOOT_COMPLETED",
                appEngineAlive = true,
            ),
        )
    }

    @Test
    fun `ignores an intent with no action at all`() {
        assertEquals(
            CallHangUpAction.Ignore,
            CallHangUpDecision.decide(action = null, appEngineAlive = true),
        )
    }
}
