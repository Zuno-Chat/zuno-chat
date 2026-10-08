package im.zuno.chat

import im.zuno.chat.VideoProbeDecision.ShownSize
import org.junit.Assert.assertEquals
import org.junit.Test

class VideoProbeDecisionTest {
    @Test
    fun `a portrait recording stored sideways is shown upright and reported rotated`() {
        assertEquals(
            ShownSize(1080, 1920, rotated = true),
            VideoProbeDecision.shownSize(1920, 1080, 90),
        )
        assertEquals(
            ShownSize(1080, 1920, rotated = true),
            VideoProbeDecision.shownSize(1920, 1080, 270),
        )
    }

    @Test
    fun `an upright portrait file is reported as not rotated`() {
        assertEquals(
            ShownSize(1080, 1920, rotated = false),
            VideoProbeDecision.shownSize(1080, 1920, 0),
        )
    }

    @Test
    fun `a half turn keeps the stored shape`() {
        assertEquals(
            ShownSize(1920, 1080, rotated = false),
            VideoProbeDecision.shownSize(1920, 1080, 180),
        )
    }

    @Test
    fun `a negative quarter turn still counts as rotated`() {
        assertEquals(
            ShownSize(1080, 1920, rotated = true),
            VideoProbeDecision.shownSize(1920, 1080, -90),
        )
    }
}
