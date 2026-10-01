package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FcmReceiveFilterTest {
    private val filter = FcmReceiveFilter()

    @Test
    fun `a new event push in the background gets the notice, the keyed lock and a warm Flutter`() {
        assertEquals(
            FcmReceivePlan(postNotice = true, wakeLockKey = "0:1%a", warmUpFlutter = true),
            filter.planFor(null, "0:1%a", eventPush = true, appInFront = false),
        )
    }

    @Test
    fun `message type gcm is a data message like a missing type`() {
        assertEquals(
            FcmReceivePlan(postNotice = true, wakeLockKey = "0:1%a", warmUpFlutter = true),
            filter.planFor("gcm", "0:1%a", eventPush = true, appInFront = false),
        )
    }

    @Test
    fun `a re-delivered message gets no notice, no lock and no record`() {
        assertNotNull(filter.planFor(null, "0:1%a", eventPush = true, appInFront = false))

        assertNull(filter.planFor(null, "0:1%a", eventPush = true, appInFront = false))
        assertNull(filter.planFor("gcm", "0:1%a", eventPush = true, appInFront = true))
    }

    @Test
    fun `deleted messages and send events take no lock and post nothing`() {
        for (type in listOf("deleted_messages", "send_event", "send_error", "other")) {
            assertNull(type, filter.planFor(type, "0:1%$type", true, appInFront = false))
        }
        assertNotNull(filter.planFor(null, "0:1%deleted_messages", true, appInFront = false))
    }

    @Test
    fun `a push without a message id is never filtered and takes no lock`() {
        val plan = FcmReceivePlan(postNotice = true, wakeLockKey = null, warmUpFlutter = true)

        assertEquals(plan, filter.planFor(null, null, eventPush = true, appInFront = false))
        assertEquals(plan, filter.planFor(null, null, eventPush = true, appInFront = false))
    }

    @Test
    fun `the app in front takes no lock and no warm-up, and the notice decides on its own`() {
        assertEquals(
            FcmReceivePlan(postNotice = true, wakeLockKey = null, warmUpFlutter = false),
            filter.planFor(null, "0:1%a", eventPush = true, appInFront = true),
        )
    }

    @Test
    fun `a badge push is recorded but gets no notice, no lock and no warm-up`() {
        val plan = FcmReceivePlan(postNotice = false, wakeLockKey = null, warmUpFlutter = false)

        assertEquals(plan, filter.planFor(null, "0:1%a", eventPush = false, appInFront = false))
        assertEquals(plan, filter.planFor(null, "0:1%b", eventPush = false, appInFront = true))
    }

    @Test
    fun `only the most recent message ids are remembered`() {
        val small = FcmReceiveFilter(capacity = 2)
        for (id in listOf("a", "b", "c")) assertNotNull(small.planFor(null, id, true, false))

        assertNull(small.planFor(null, "c", true, false))
        assertNull(small.planFor(null, "b", true, false))
        assertNotNull(small.planFor(null, "a", true, false))
    }

    @Test
    fun `a repeat counts as recent, so a burst of re-deliveries stays filtered`() {
        val small = FcmReceiveFilter(capacity = 2)
        assertNotNull(small.planFor(null, "a", true, false))
        assertNotNull(small.planFor(null, "b", true, false))
        assertNull(small.planFor(null, "a", true, false))
        assertNotNull(small.planFor(null, "c", true, false))

        assertNull(small.planFor(null, "a", true, false))
        assertNotNull(small.planFor(null, "b", true, false))
    }

    @Test
    fun `the filter remembers more ids than the FCM SDK's own duplicate check`() {
        assertTrue(FcmReceiveFilter.RECENT_MESSAGE_IDS >= FCM_SDK_RECENT_IDS)
    }

    private companion object {
        const val FCM_SDK_RECENT_IDS = 10
    }
}
