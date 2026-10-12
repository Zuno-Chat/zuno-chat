package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class OutboundShareDecisionTest {
    @Test
    fun `one file is shared as its own type`() {
        assertEquals("image/png", OutboundShareDecision.intentType(listOf("image/png")))
    }

    @Test
    fun `files of one type are shared as that type`() {
        assertEquals(
            "application/pdf",
            OutboundShareDecision.intentType(listOf("application/pdf", "application/pdf")),
        )
    }

    @Test
    fun `files of one family are shared as that family`() {
        assertEquals(
            "image/*",
            OutboundShareDecision.intentType(listOf("image/png", "image/jpeg")),
        )
    }

    @Test
    fun `files of different families are shared as anything`() {
        assertEquals(
            "*/*",
            OutboundShareDecision.intentType(listOf("image/png", "video/mp4")),
        )
    }

    @Test
    fun `a file without a usable type makes the share anything`() {
        assertEquals("*/*", OutboundShareDecision.intentType(listOf(null)))
        assertEquals("*/*", OutboundShareDecision.intentType(listOf("image/png", "")))
        assertEquals("*/*", OutboundShareDecision.intentType(listOf("image/png", "png")))
        assertEquals("*/*", OutboundShareDecision.intentType(listOf("image/*", "image/png")))
        assertEquals("*/*", OutboundShareDecision.intentType(emptyList()))
    }
}
