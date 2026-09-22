package im.zuno.chat.zuno_vibration

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class VibrationAmplitudesTest {
    @Test
    fun `on segments run at full strength and off segments stay silent`() {
        assertArrayEquals(
            intArrayOf(0, 255, 0, 255),
            VibrationAmplitudes.forPattern(longArrayOf(0, 300, 150, 300)),
        )
    }

    @Test
    fun `the ring pattern's trailing pause is silent too`() {
        assertArrayEquals(
            intArrayOf(0, 255, 0, 255, 0),
            VibrationAmplitudes.forPattern(longArrayOf(0, 800, 500, 800, 2000)),
        )
    }

    @Test
    fun `an empty pattern has no amplitudes`() {
        assertArrayEquals(intArrayOf(), VibrationAmplitudes.forPattern(longArrayOf()))
    }
}
