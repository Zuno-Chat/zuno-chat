package im.zuno.chat

import im.zuno.chat.zuno_notifications.PushKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FcmReceiveFilterTest {
    private val filter = FcmReceiveFilter()

    @Test
    fun `a background data message, gcm or untyped, gets the notice, lock and warm Flutter`() {
        for (type in listOf(null, "gcm")) {
            assertEquals(
                "$type",
                FcmReceivePlan.MessageNotice(wakeLockKey = "0:1%$type", warmUpFlutter = true),
                filter.planFor(type, "0:1%$type", PushKind.MESSAGE, appInFront = false, arrivedAtElapsedMs = 0L),
            )
        }
    }

    @Test
    fun `a ring push posts no notice but warms Flutter, in front or not`() {
        assertEquals(
            FcmReceivePlan.RingWarmUp,
            filter.planFor(null, "0:1%ring", PushKind.RING, appInFront = false, arrivedAtElapsedMs = 0L),
        )
        assertEquals(
            FcmReceivePlan.RingWarmUp,
            filter.planFor(null, "0:2%ring", PushKind.RING, appInFront = true, arrivedAtElapsedMs = 0L),
        )
    }

    @Test
    fun `a ring end is ended at once and warms no Flutter, in front or not`() {
        assertEquals(
            FcmReceivePlan.RingEnd,
            filter.planFor(null, "0:1%end", PushKind.RING_END, appInFront = false, arrivedAtElapsedMs = 0L),
        )
        assertEquals(
            FcmReceivePlan.RingEnd,
            filter.planFor(null, "0:2%end", PushKind.RING_END, appInFront = true, arrivedAtElapsedMs = 0L),
        )
    }

    @Test
    fun `a re-delivered message gets no notice, no lock and no record`() {
        assertNotNull(filter.planFor(null, "0:1%a", PushKind.MESSAGE, appInFront = false, arrivedAtElapsedMs = 0L))

        assertNull(filter.planFor(null, "0:1%a", PushKind.MESSAGE, appInFront = false, arrivedAtElapsedMs = 0L))
        assertNull(filter.planFor("gcm", "0:1%a", PushKind.MESSAGE, appInFront = true, arrivedAtElapsedMs = 0L))
    }

    @Test
    fun `deleted messages and send events take no lock and post nothing`() {
        for (type in listOf("deleted_messages", "send_event", "send_error", "other")) {
            assertNull(
                type,
                filter.planFor(type, "0:1%$type", PushKind.MESSAGE, appInFront = false, arrivedAtElapsedMs = 0L),
            )
        }
        assertNotNull(
            filter.planFor(null, "0:1%deleted_messages", PushKind.MESSAGE, appInFront = false, arrivedAtElapsedMs = 0L),
        )
    }

    @Test
    fun `a push without a message id is never filtered and takes no lock`() {
        val plan = FcmReceivePlan.MessageNotice(wakeLockKey = null, warmUpFlutter = true)

        assertEquals(plan, filter.planFor(null, null, PushKind.MESSAGE, appInFront = false, arrivedAtElapsedMs = 0L))
        assertEquals(plan, filter.planFor(null, null, PushKind.MESSAGE, appInFront = false, arrivedAtElapsedMs = 0L))
    }

    @Test
    fun `the app in front takes no lock and no warm-up, and the notice decides on its own`() {
        assertEquals(
            FcmReceivePlan.MessageNotice(wakeLockKey = null, warmUpFlutter = false),
            filter.planFor(null, "0:1%a", PushKind.MESSAGE, appInFront = true, arrivedAtElapsedMs = 0L),
        )
    }

    @Test
    fun `a badge push is recorded but gets no notice, no lock and no warm-up`() {
        assertEquals(
            FcmReceivePlan.RecordOnly,
            filter.planFor(null, "0:1%a", PushKind.BADGE, appInFront = false, arrivedAtElapsedMs = 0L),
        )
        assertEquals(
            FcmReceivePlan.RecordOnly,
            filter.planFor(null, "0:1%b", PushKind.BADGE, appInFront = true, arrivedAtElapsedMs = 0L),
        )
    }

    @Test
    fun `a test push gets only the test notice, whether or not the app is in front`() {
        assertEquals(
            FcmReceivePlan.TestNotice,
            filter.planFor(null, "0:1%t", PushKind.TEST, appInFront = false, arrivedAtElapsedMs = 0L),
        )
        assertEquals(
            FcmReceivePlan.TestNotice,
            filter.planFor(null, "0:1%u", PushKind.TEST, appInFront = true, arrivedAtElapsedMs = 0L),
        )
    }

    @Test
    fun `a re-delivered test push gets no second notice and no second record`() {
        assertNotNull(filter.planFor(null, "0:1%t", PushKind.TEST, appInFront = true, arrivedAtElapsedMs = 0L))

        assertNull(filter.planFor(null, "0:1%t", PushKind.TEST, appInFront = true, arrivedAtElapsedMs = 0L))
        assertNull(filter.planFor("gcm", "0:1%t", PushKind.TEST, appInFront = false, arrivedAtElapsedMs = 0L))
    }

    @Test
    fun `a test push that is not a data message posts nothing`() {
        assertNull(filter.planFor("deleted_messages", "0:1%t", PushKind.TEST, appInFront = false, arrivedAtElapsedMs = 0L))
    }

    @Test
    fun `only the most recent message ids are remembered`() {
        val small = FcmReceiveFilter(capacity = 2)
        for (id in listOf("a", "b", "c")) {
            assertNotNull(small.planFor(null, id, PushKind.MESSAGE, false, arrivedAtElapsedMs = 0L))
        }

        assertNull(small.planFor(null, "c", PushKind.MESSAGE, false, arrivedAtElapsedMs = 0L))
        assertNull(small.planFor(null, "b", PushKind.MESSAGE, false, arrivedAtElapsedMs = 0L))
        assertNotNull(small.planFor(null, "a", PushKind.MESSAGE, false, arrivedAtElapsedMs = 0L))
    }

    @Test
    fun `a repeat counts as recent, so a burst of re-deliveries stays filtered`() {
        val small = FcmReceiveFilter(capacity = 2)
        assertNotNull(small.planFor(null, "a", PushKind.MESSAGE, false, arrivedAtElapsedMs = 0L))
        assertNotNull(small.planFor(null, "b", PushKind.MESSAGE, false, arrivedAtElapsedMs = 0L))
        assertNull(small.planFor(null, "a", PushKind.MESSAGE, false, arrivedAtElapsedMs = 0L))
        assertNotNull(small.planFor(null, "c", PushKind.MESSAGE, false, arrivedAtElapsedMs = 0L))

        assertNull(small.planFor(null, "a", PushKind.MESSAGE, false, arrivedAtElapsedMs = 0L))
        assertNotNull(small.planFor(null, "b", PushKind.MESSAGE, false, arrivedAtElapsedMs = 0L))
    }

    @Test
    fun `remembers when each message first reached the phone, a re-delivery changing nothing`() {
        filter.planFor(null, "0:1%a", PushKind.MESSAGE, false, arrivedAtElapsedMs = 1_000L)
        filter.planFor(null, "0:1%a", PushKind.MESSAGE, false, arrivedAtElapsedMs = 9_000L)

        assertEquals(1_000L, filter.arrivedAt("0:1%a"))
        assertNull(filter.arrivedAt("0:1%unknown"))
        assertNull(filter.arrivedAt(null))
    }

    @Test
    fun `the filter remembers more ids than the FCM SDK's own duplicate check`() {
        assertTrue(FcmReceiveFilter.RECENT_MESSAGE_IDS >= FCM_SDK_RECENT_IDS)
    }

    private companion object {
        const val FCM_SDK_RECENT_IDS = 10
    }
}
