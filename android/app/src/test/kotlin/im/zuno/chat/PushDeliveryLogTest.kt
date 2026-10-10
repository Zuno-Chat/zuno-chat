package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PushDeliveryLogTest {
    private val received = PushDelivery(
        receivedAtMs = 2_000,
        sentAtMs = 1_500,
        originalPriority = "high",
        deliveredPriority = "normal",
        deviceIdle = true,
        standbyBucket = 10,
        receiverMs = 12,
        noticePosted = true,
    )

    @Test
    fun `a full delivery becomes one tab-separated line`() {
        val line = PushDeliveryLog.lineFor(
            received.copy(serviceStartMs = 40, handling = FcmPushHandling.DART, ackMs = 2_340),
        )
        assertEquals("2000\t1500\thigh\tnormal\t1\t10\t12\t1\t40\tdart\t2340", line)
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
        assertEquals("2000\t\t\t\t0\t\t\t\t\t\t", line)
    }

    @Test
    fun `a notice the receiver did not post reads 0, an unknown one stays empty`() {
        val notPosted = PushDeliveryLog.lineFor(received.copy(noticePosted = false))
        val unknown = PushDeliveryLog.lineFor(received.copy(noticePosted = null))

        assertEquals("0", notPosted.split('\t')[7])
        assertEquals("", unknown.split('\t')[7])
    }

    @Test
    fun `the service start and Dart's ack are measured from the receiver`() {
        val done = PushDeliveryLog.completed(
            PendingDelivery(received, receivedAtElapsedMs = 50_000),
            PushServiceTiming(
                startedAtElapsedMs = 50_040,
                handling = FcmPushHandling.DART,
                ackedAtElapsedMs = 52_340,
            ),
        )

        assertEquals(
            received.copy(serviceStartMs = 40, handling = FcmPushHandling.DART, ackMs = 2_340),
            done,
        )
    }

    @Test
    fun `an ack that never came and a push handled natively have no ack time`() {
        val pending = PendingDelivery(received, receivedAtElapsedMs = 50_000)

        val late = PushDeliveryLog.completed(
            pending,
            PushServiceTiming(50_040, FcmPushHandling.DART, ackedAtElapsedMs = null),
        )
        val badge = PushDeliveryLog.completed(
            pending,
            PushServiceTiming(50_040, FcmPushHandling.CLEAR_MESSAGES, ackedAtElapsedMs = null),
        )

        assertNull(late.ackMs)
        assertEquals(FcmPushHandling.DART, late.handling)
        assertNull(badge.ackMs)
        assertEquals("clear", PushDeliveryLog.lineFor(badge).split('\t')[9])
    }

    @Test
    fun `timings never go negative`() {
        val done = PushDeliveryLog.completed(
            PendingDelivery(received, receivedAtElapsedMs = 50_000),
            PushServiceTiming(49_990, FcmPushHandling.DART, ackedAtElapsedMs = 49_995),
        )

        assertEquals(0L, done.serviceStartMs)
        assertEquals(0L, done.ackMs)
    }

    @Test
    fun `the completed line replaces the receiver's line in place`() {
        val log = PushDeliveryLog.replace("c\nb\na", old = "b", new = "B")

        assertEquals("c\nB\na", log)
    }

    @Test
    fun `only the newest of two identical lines is completed`() {
        assertEquals("B\nb", PushDeliveryLog.replace("b\nb", old = "b", new = "B"))
    }

    @Test
    fun `a line no longer in the log is not brought back`() {
        assertNull(PushDeliveryLog.replace("c\na", old = "b", new = "B"))
        assertNull(PushDeliveryLog.replace(null, old = "b", new = "B"))
    }

    @Test
    fun `a pending delivery is taken once`() {
        val pending = PendingDeliveries(capacity = 4)
        val entry = PendingDelivery(received, receivedAtElapsedMs = 1)
        pending.put("0:1%a", entry)

        assertEquals(entry, pending.take("0:1%a"))
        assertNull(pending.take("0:1%a"))
        assertNull(pending.take("0:1%b"))
    }

    @Test
    fun `pending deliveries the service never completes are dropped oldest first`() {
        val pending = PendingDeliveries(capacity = 2)
        for (id in listOf("a", "b", "c")) pending.put(id, PendingDelivery(received, 1))

        assertNull(pending.take("a"))
        assertEquals(PendingDelivery(received, 1), pending.take("b"))
        assertEquals(PendingDelivery(received, 1), pending.take("c"))
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
