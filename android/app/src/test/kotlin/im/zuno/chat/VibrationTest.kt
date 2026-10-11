package im.zuno.chat

import im.zuno.chat.zuno_notifications.Vibration
import org.junit.Assert.assertArrayEquals
import org.junit.Test

class VibrationTest {
    @Test
    fun `buzzes run at full strength and the pauses between them stay silent`() {
        assertArrayEquals(
            intArrayOf(0, 255, 0, 255, 0),
            Vibration.amplitudes(longArrayOf(0, 800, 500, 800, 2000)),
        )
        assertArrayEquals(intArrayOf(), Vibration.amplitudes(longArrayOf()))
    }
}
