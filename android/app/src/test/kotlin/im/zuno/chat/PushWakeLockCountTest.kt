package im.zuno.chat

import im.zuno.chat.zuno_notifications.PushWakeLockCount
import org.junit.Assert.assertEquals
import org.junit.Test

class PushWakeLockCountTest {
    @Test
    fun `each push while the lock is held adds a holder`() {
        assertEquals(3, PushWakeLockCount.afterAcquire(holders = 2, held = true))
    }

    @Test
    fun `a lock that timed out starts counting again from one`() {
        assertEquals(1, PushWakeLockCount.afterAcquire(holders = 5, held = false))
    }

    @Test
    fun `releases never go below zero`() {
        assertEquals(1, PushWakeLockCount.afterRelease(2))
        assertEquals(0, PushWakeLockCount.afterRelease(1))
        assertEquals(0, PushWakeLockCount.afterRelease(0))
    }
}
