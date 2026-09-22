package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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

    @Test
    fun `hangs up when the host is destroyed mid-call`() {
        assertTrue(CallHangUpDecision.onHostDestroyed(callActive = true, hangUpRequested = false))
    }

    @Test
    fun `does not hang up twice when picture-in-picture close already asked`() {
        assertFalse(CallHangUpDecision.onHostDestroyed(callActive = true, hangUpRequested = true))
    }

    @Test
    fun `does nothing when no call is active`() {
        assertFalse(CallHangUpDecision.onHostDestroyed(callActive = false, hangUpRequested = false))
    }
}
