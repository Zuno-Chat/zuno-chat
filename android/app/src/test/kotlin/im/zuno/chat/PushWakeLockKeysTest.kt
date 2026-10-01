package im.zuno.chat

import im.zuno.chat.zuno_notifications.PushWakeLockKeys
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PushWakeLockKeysTest {
    private val keys = PushWakeLockKeys(timeoutMs = 30_000)

    @Test
    fun `the lock is let go when its only push is done`() {
        keys.acquire("m1", now = 0)

        assertTrue(keys.release("m1", now = 1_000))
    }

    @Test
    fun `the lock stays while another push still needs it`() {
        keys.acquire("m1", now = 0)
        keys.acquire("m2", now = 100)

        assertFalse(keys.release("m1", now = 1_000))
        assertTrue(keys.release("m2", now = 2_000))
    }

    @Test
    fun `releasing the same push twice never lets go of another push's hold`() {
        keys.acquire("m1", now = 0)
        keys.acquire("m2", now = 100)

        assertFalse(keys.release("m1", now = 1_000))
        assertFalse(keys.release("m1", now = 1_100))
        assertTrue(keys.release("m2", now = 1_200))
    }

    @Test
    fun `a release for a push that never took the lock changes nothing`() {
        keys.acquire("m1", now = 0)

        assertFalse(keys.release("in-front", now = 1_000))
        assertTrue(keys.release("m1", now = 1_100))
    }

    @Test
    fun `a hold past the timeout no longer keeps the lock`() {
        keys.acquire("stuck", now = 0)
        keys.acquire("m2", now = 10_000)

        assertTrue(keys.release("m2", now = 30_000))
    }

    @Test
    fun `a push taken again refreshes its own hold`() {
        keys.acquire("m1", now = 0)
        keys.acquire("m1", now = 20_000)
        keys.acquire("m2", now = 21_000)

        assertFalse(keys.release("m2", now = 40_000))
        assertTrue(keys.release("m1", now = 41_000))
    }
}
