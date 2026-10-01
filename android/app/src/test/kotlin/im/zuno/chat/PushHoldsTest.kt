package im.zuno.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PushHoldsTest {
    private val holds = PushHolds(timeoutMs = 30_000, writeOffMs = 300_000)

    @Test
    fun `the lock is let go when its only push is done`() {
        holds.acquire(key = "a", now = 0)

        assertTrue(holds.release(key = null, now = 1_000))
    }

    @Test
    fun `the lock stays while another push still needs it`() {
        holds.acquire(key = "a", now = 0)
        holds.acquire(key = "b", now = 100)

        assertFalse(holds.release(key = null, now = 1_000))
        assertTrue(holds.release(key = null, now = 2_000))
    }

    @Test
    fun `an older push's late release never lets go of a newer push's hold`() {
        holds.acquire(key = "old", now = 0)
        holds.acquire(key = "new", now = 35_000)

        assertFalse(holds.release(key = null, now = 40_000))
        assertTrue(holds.release(key = null, now = 45_000))
    }

    @Test
    fun `a hold past its timeout no longer keeps the lock`() {
        holds.acquire(key = "stuck", now = 0)
        holds.acquire(key = "b", now = 10_000)

        assertTrue(holds.release(key = "b", now = 30_000))
    }

    @Test
    fun `a release naming its push lets go of that push only`() {
        holds.acquire(key = "a", now = 0)
        holds.acquire(key = "b", now = 100)

        assertFalse(holds.release(key = "b", now = 1_000))
        assertTrue(holds.release(key = "a", now = 2_000))
    }

    @Test
    fun `a release naming a push that holds nothing changes nothing`() {
        holds.acquire(key = "a", now = 0)

        assertFalse(holds.release(key = "replayed", now = 1_000))
        assertTrue(holds.release(key = "a", now = 1_100))
    }

    @Test
    fun `the same push held twice needs two releases`() {
        holds.acquire(key = "a", now = 0)
        holds.acquire(key = "a", now = 100)

        assertFalse(holds.release(key = "a", now = 1_000))
        assertTrue(holds.release(key = "a", now = 1_100))
    }

    @Test
    fun `a push without an event id is held and let go like any other`() {
        holds.acquire(key = null, now = 0)
        holds.acquire(key = "a", now = 100)

        assertFalse(holds.release(key = "a", now = 1_000))
        assertTrue(holds.release(key = null, now = 1_100))
    }

    @Test
    fun `a hold whose release never came is written off in the end`() {
        holds.acquire(key = "lost", now = 0)
        holds.acquire(key = "b", now = 400_000)

        assertTrue(holds.release(key = null, now = 401_000))
    }
}
