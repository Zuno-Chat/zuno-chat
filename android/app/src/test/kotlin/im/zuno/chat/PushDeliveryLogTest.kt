package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PushDeliveryLogTest {
    @Test
    fun `a full delivery becomes one tab-separated line`() {
        val line = PushDeliveryLog.lineFor(
            PushDelivery(
                receivedAtMs = 2_000,
                sentAtMs = 1_500,
                originalPriority = "high",
                deliveredPriority = "normal",
                deviceIdle = true,
                standbyBucket = 10,
            ),
        )
        assertEquals("2000\t1500\thigh\tnormal\t1\t10", line)
    }

    @Test
    fun `missing fields stay as empty columns`() {
        val line = PushDeliveryLog.lineFor(
            PushDelivery(
                receivedAtMs = 2_000,
                sentAtMs = null,
                originalPriority = null,
                deliveredPriority = null,
                deviceIdle = false,
                standbyBucket = null,
            ),
        )
        assertEquals("2000\t\t\t\t0\t", line)
    }

    @Test
    fun `the sent time is read from a long or a numeric string only`() {
        assertEquals(1_500L, PushDeliveryLog.sentAtFrom(1_500L))
        assertEquals(1_500L, PushDeliveryLog.sentAtFrom("1500"))
        assertNull(PushDeliveryLog.sentAtFrom("soon"))
        assertNull(PushDeliveryLog.sentAtFrom(null))
    }

    @Test
    fun `the newest line goes first and the log keeps a fixed number`() {
        val log = PushDeliveryLog.prepend("b\nc", "a", max = 2)
        assertEquals("a\nb", log)
    }

    @Test
    fun `an empty or blank log starts fresh`() {
        assertEquals("a", PushDeliveryLog.prepend(null, "a"))
        assertEquals("a", PushDeliveryLog.prepend("\n\n", "a"))
    }
}
