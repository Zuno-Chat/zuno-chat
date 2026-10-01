package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FcmPushKeysTest {
    @Test
    fun `the notice receiver and the service pair a push by its message id`() {
        assertEquals("0:1700000000000%abc", FcmPushKeys.messageId("0:1700000000000%abc"))
    }

    @Test
    fun `a push without a message id has no key`() {
        assertNull(FcmPushKeys.messageId(null))
        assertNull(FcmPushKeys.messageId(""))
    }

    @Test
    fun `a new token reaches Dart only when a registration exists and differs`() {
        assertTrue(FcmPushKeys.shouldForwardToken(registered = "old", fresh = "new"))
        assertFalse(FcmPushKeys.shouldForwardToken(registered = "same", fresh = "same"))
        assertFalse(FcmPushKeys.shouldForwardToken(registered = null, fresh = "new"))
        assertFalse(FcmPushKeys.shouldForwardToken(registered = "", fresh = "new"))
    }
}
