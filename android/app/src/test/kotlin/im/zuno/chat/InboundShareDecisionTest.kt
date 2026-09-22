package im.zuno.chat

import im.zuno.chat.InboundShareDecision.SharedFile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class InboundShareDecisionTest {
    @Test
    fun `a specific per-item mime wins`() {
        assertEquals("image/png", InboundShareDecision.mimeTypeFor("image/png", "image/jpeg", "image/*"))
    }

    @Test
    fun `wildcards are skipped in favour of the resolver, then the intent type`() {
        assertEquals("image/jpeg", InboundShareDecision.mimeTypeFor("image/*", "image/jpeg", "*/*"))
        assertEquals("video/mp4", InboundShareDecision.mimeTypeFor(null, null, "video/mp4"))
        assertNull(InboundShareDecision.mimeTypeFor("*/*", "", "image/*"))
    }

    @Test
    fun `display name wins over the uri`() {
        assertEquals("holiday.jpg", InboundShareDecision.fileName("holiday.jpg", "content://x/y/123"))
    }

    @Test
    fun `without a display name the decoded last uri segment is used`() {
        assertEquals("image:123", InboundShareDecision.fileName(null, "content://media/document/image%3A123"))
        assertEquals("123", InboundShareDecision.fileName("  ", "content://x/y/123?size=1"))
        assertEquals("shared", InboundShareDecision.fileName(null, "content://"))
    }

    @Test
    fun `names are made safe for the filesystem`() {
        assertEquals("a_b.txt", InboundShareDecision.safeFileName("a/b.txt"))
        assertEquals("a_b.txt", InboundShareDecision.safeFileName("a\\b.txt"))
        assertEquals(".._.._x", InboundShareDecision.safeFileName("../../x"))
        assertEquals("shared", InboundShareDecision.safeFileName(".."))
        assertEquals("shared", InboundShareDecision.safeFileName("."))
        assertEquals("shared", InboundShareDecision.safeFileName(""))
        assertEquals(".env", InboundShareDecision.safeFileName(".env"))
    }

    @Test
    fun `payload is null when nothing was shared`() {
        assertNull(InboundShareDecision.payload("  ", emptyList()))
        assertNull(InboundShareDecision.payload(null, emptyList()))
    }

    @Test
    fun `payload carries text and file maps`() {
        val payload = InboundShareDecision.payload(
            "https://example.org",
            listOf(SharedFile("content://a/1", "a.jpg", "image/jpeg"), SharedFile("content://a/2", "b.bin", null)),
        )!!
        assertEquals("https://example.org", payload["text"])
        val files = payload["files"] as List<*>
        assertEquals(mapOf("uri" to "content://a/1", "name" to "a.jpg", "mimeType" to "image/jpeg"), files[0])
        assertEquals(mapOf("uri" to "content://a/2", "name" to "b.bin", "mimeType" to null), files[1])
    }
}
