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
    fun `a new message push in the background gets the notice, the lock and a warm Flutter`() {
        assertEquals(
            FcmReceivePlan.MessageNotice(wakeLockKey = "0:1%a", warmUpFlutter = true),
            filter.planFor(null, "0:1%a", PushKind.MESSAGE, appInFront = false),
        )
    }

    @Test
    fun `message type gcm is a data message like a missing type`() {
        assertEquals(
            FcmReceivePlan.MessageNotice(wakeLockKey = "0:1%a", warmUpFlutter = true),
            filter.planFor("gcm", "0:1%a", PushKind.MESSAGE, appInFront = false),
        )
    }

    @Test
    fun `a re-delivered message gets no notice, no lock and no record`() {
        assertNotNull(filter.planFor(null, "0:1%a", PushKind.MESSAGE, appInFront = false))

        assertNull(filter.planFor(null, "0:1%a", PushKind.MESSAGE, appInFront = false))
        assertNull(filter.planFor("gcm", "0:1%a", PushKind.MESSAGE, appInFront = true))
    }

    @Test
    fun `deleted messages and send events take no lock and post nothing`() {
        for (type in listOf("deleted_messages", "send_event", "send_error", "other")) {
            assertNull(
                type,
                filter.planFor(type, "0:1%$type", PushKind.MESSAGE, appInFront = false),
            )
        }
        assertNotNull(
            filter.planFor(null, "0:1%deleted_messages", PushKind.MESSAGE, appInFront = false),
        )
    }

    @Test
    fun `a push without a message id is never filtered and takes no lock`() {
        val plan = FcmReceivePlan.MessageNotice(wakeLockKey = null, warmUpFlutter = true)

        assertEquals(plan, filter.planFor(null, null, PushKind.MESSAGE, appInFront = false))
        assertEquals(plan, filter.planFor(null, null, PushKind.MESSAGE, appInFront = false))
    }

    @Test
    fun `the app in front takes no lock and no warm-up, and the notice decides on its own`() {
        assertEquals(
            FcmReceivePlan.MessageNotice(wakeLockKey = null, warmUpFlutter = false),
            filter.planFor(null, "0:1%a", PushKind.MESSAGE, appInFront = true),
        )
    }

    @Test
    fun `a badge push is recorded but gets no notice, no lock and no warm-up`() {
        assertEquals(
            FcmReceivePlan.RecordOnly,
            filter.planFor(null, "0:1%a", PushKind.BADGE, appInFront = false),
        )
        assertEquals(
            FcmReceivePlan.RecordOnly,
            filter.planFor(null, "0:1%b", PushKind.BADGE, appInFront = true),
        )
    }

    @Test
    fun `a test push gets only the test notice, whether or not the app is in front`() {
        assertEquals(
            FcmReceivePlan.TestNotice,
            filter.planFor(null, "0:1%t", PushKind.TEST, appInFront = false),
        )
        assertEquals(
            FcmReceivePlan.TestNotice,
            filter.planFor(null, "0:1%u", PushKind.TEST, appInFront = true),
        )
    }

    @Test
    fun `a re-delivered test push gets no second notice and no second record`() {
        assertNotNull(filter.planFor(null, "0:1%t", PushKind.TEST, appInFront = true))

        assertNull(filter.planFor(null, "0:1%t", PushKind.TEST, appInFront = true))
        assertNull(filter.planFor("gcm", "0:1%t", PushKind.TEST, appInFront = false))
    }

    @Test
    fun `a test push that is not a data message posts nothing`() {
        assertNull(filter.planFor("deleted_messages", "0:1%t", PushKind.TEST, appInFront = false))
    }

    @Test
    fun `only the most recent message ids are remembered`() {
        val small = FcmReceiveFilter(capacity = 2)
        for (id in listOf("a", "b", "c")) {
            assertNotNull(small.planFor(null, id, PushKind.MESSAGE, false))
        }

        assertNull(small.planFor(null, "c", PushKind.MESSAGE, false))
        assertNull(small.planFor(null, "b", PushKind.MESSAGE, false))
        assertNotNull(small.planFor(null, "a", PushKind.MESSAGE, false))
    }

    @Test
    fun `a repeat counts as recent, so a burst of re-deliveries stays filtered`() {
        val small = FcmReceiveFilter(capacity = 2)
        assertNotNull(small.planFor(null, "a", PushKind.MESSAGE, false))
        assertNotNull(small.planFor(null, "b", PushKind.MESSAGE, false))
        assertNull(small.planFor(null, "a", PushKind.MESSAGE, false))
        assertNotNull(small.planFor(null, "c", PushKind.MESSAGE, false))

        assertNull(small.planFor(null, "a", PushKind.MESSAGE, false))
        assertNotNull(small.planFor(null, "b", PushKind.MESSAGE, false))
    }

    @Test
    fun `the filter remembers more ids than the FCM SDK's own duplicate check`() {
        assertTrue(FcmReceiveFilter.RECENT_MESSAGE_IDS >= FCM_SDK_RECENT_IDS)
    }

    private companion object {
        const val FCM_SDK_RECENT_IDS = 10
    }
}
