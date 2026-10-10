package im.zuno.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PushHoldsTest {
    private val holds = PushHolds(timeoutMs = 30_000, writeOffMs = 300_000)

    @Test
    fun `the lock is let go when its only push is done`() {
        holds.acquire(key = "a", now = 0)

        assertTrue(holds.release(key = "a", now = 1_000))
    }

    @Test
    fun `the lock stays while another push still needs it`() {
        holds.acquire(key = "a", now = 0)
        holds.acquire(key = "b", now = 100)

        assertFalse(holds.release(key = "a", now = 1_000))
        assertTrue(holds.release(key = "b", now = 2_000))
    }

    @Test
    fun `the same push taken twice needs a release for each`() {
        holds.acquire(key = "a", now = 0)
        holds.acquire(key = "a", now = 100)

        assertFalse(holds.release(key = "a", now = 1_000))
        assertTrue(holds.release(key = "a", now = 1_100))
    }

    @Test
    fun `a release for a push that holds nothing changes nothing`() {
        assertFalse(holds.release(key = "never-held", now = 0))

        holds.acquire(key = "a", now = 100)

        assertFalse(holds.release(key = "never-held", now = 1_000))
        assertFalse(holds.release(key = null, now = 1_100))
        assertTrue(holds.release(key = "a", now = 1_200))
    }

    @Test
    fun `a push without an event id is let go only by a release without one`() {
        holds.acquire(key = null, now = 0)
        holds.acquire(key = "a", now = 100)

        assertFalse(holds.release(key = "a", now = 1_000))
        assertTrue(holds.release(key = "", now = 1_100))
    }

    @Test
    fun `a hold past the timeout no longer keeps the lock`() {
        holds.acquire(key = "stuck", now = 0)
        holds.acquire(key = "b", now = 10_000)

        assertTrue(holds.release(key = "b", now = 30_000))
    }

    @Test
    fun `a late release takes its push's oldest hold, never a newer one`() {
        holds.acquire(key = "a", now = 0)
        holds.acquire(key = "a", now = 35_000)

        assertFalse(holds.release(key = "a", now = 40_000))
        assertTrue(holds.release(key = "a", now = 45_000))
    }

    @Test
    fun `a hold whose release never came is written off in the end`() {
        holds.acquire(key = "a", now = 0)
        holds.acquire(key = "a", now = 300_000)

        assertTrue(holds.release(key = "a", now = 301_000))
    }
}
