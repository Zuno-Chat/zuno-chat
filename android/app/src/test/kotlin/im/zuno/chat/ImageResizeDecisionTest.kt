package im.zuno.chat

import im.zuno.chat.ImageResizeDecision.Size
import org.junit.Assert.assertEquals
import org.junit.Test

class ImageResizeDecisionTest {
    @Test
    fun `a landscape photo is capped on its long edge`() {
        assertEquals(Size(1080, 810), ImageResizeDecision.targetSize(4000, 3000, 1080))
    }

    @Test
    fun `a portrait photo is capped on its long edge`() {
        assertEquals(Size(810, 1080), ImageResizeDecision.targetSize(3000, 4000, 1080))
    }

    @Test
    fun `an image already within the cap is left alone`() {
        assertEquals(Size(640, 480), ImageResizeDecision.targetSize(640, 480, 1080))
        assertEquals(Size(1080, 1080), ImageResizeDecision.targetSize(1080, 1080, 1080))
    }

    @Test
    fun `a very thin image never collapses to zero`() {
        assertEquals(Size(1080, 1), ImageResizeDecision.targetSize(20000, 2, 1080))
    }

    @Test
    fun `sample size is the largest power of two that stays at or above the target`() {
        assertEquals(2, ImageResizeDecision.sampleSize(4000, 3000, Size(1080, 810)))
        assertEquals(4, ImageResizeDecision.sampleSize(8000, 6000, Size(1080, 810)))
        assertEquals(1, ImageResizeDecision.sampleSize(1080, 810, Size(1080, 810)))
        assertEquals(1, ImageResizeDecision.sampleSize(2000, 1500, Size(1080, 810)))
    }
}
