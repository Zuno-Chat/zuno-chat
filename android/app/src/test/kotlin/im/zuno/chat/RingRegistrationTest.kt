package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RingRegistrationTest {
    private val keys = RingKeys(kid = 7L, key = ByteArray(32) { it.toByte() })

    @Test
    fun `status names the FCM token and the current key`() {
        val status = RingRegistration.status("fcm-token", keys)

        assertEquals("fcm-token", status["token"])
        assertEquals("production", status["environment"])
        assertEquals(7L, status["kid"])
        assertEquals("AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", status["key"])
        assertEquals(true, status["rings"])
    }

    @Test
    fun `without a key the status says this phone cannot ring from the server`() {
        assertEquals(false, RingRegistration.status("fcm-token", null)["rings"])
        assertEquals(0L, RingRegistration.status(null, null)["kid"])
        assertNull(RingRegistration.status(null, keys)["token"])
    }

    @Test
    fun `events queue in order, once each, and come out as a list`() {
        val queued = RingRegistration.withEvent(
            RingRegistration.withEvent(
                RingRegistration.withEvent(null, "token"),
                "keyMismatch",
            ),
            "token",
        )

        assertEquals(listOf("token", "keyMismatch"), RingRegistration.eventsIn(queued))
        assertEquals(emptyList<String>(), RingRegistration.eventsIn(null))
    }
}
