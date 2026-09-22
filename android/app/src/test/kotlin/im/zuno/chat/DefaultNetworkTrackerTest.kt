package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DefaultNetworkTrackerTest {
    @Test
    fun `a new default network is available`() {
        assertEquals(true, DefaultNetworkTracker<String>().onAvailable("wifi"))
    }

    @Test
    fun `losing the current default network reports unavailable`() {
        val tracker = DefaultNetworkTracker<String>()
        tracker.onAvailable("wifi")

        assertEquals(false, tracker.onLost("wifi"))
    }

    @Test
    fun `losing a network already replaced as default reports nothing`() {
        val tracker = DefaultNetworkTracker<String>()
        tracker.onAvailable("wifi")
        tracker.onAvailable("cellular")

        assertNull(tracker.onLost("wifi"))
    }

    @Test
    fun `a loss with no known default network reports nothing`() {
        assertNull(DefaultNetworkTracker<String>().onLost("wifi"))
    }

    @Test
    fun `a network lost twice reports unavailable only once`() {
        val tracker = DefaultNetworkTracker<String>()
        tracker.onAvailable("wifi")
        tracker.onLost("wifi")

        assertNull(tracker.onLost("wifi"))
    }
}
