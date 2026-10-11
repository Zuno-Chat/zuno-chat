package im.zuno.chat

import im.zuno.chat.InboundShareDecision.SharedFile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class InboundShareDecisionTest {
    @Test
    fun `a specific per-item mime wins`() {
        assertEquals(
            "image/png",
            InboundShareDecision.mimeTypeFor("image/png", "image/jpeg", "image/*"),
        )
    }

    @Test
    fun `wildcards are skipped in favour of the resolver, then the intent type`() {
        assertEquals("image/jpeg", InboundShareDecision.mimeTypeFor("image/*", "image/jpeg", "*/*"))
        assertEquals("video/mp4", InboundShareDecision.mimeTypeFor(null, null, "video/mp4"))
        assertNull(InboundShareDecision.mimeTypeFor("*/*", "", "image/*"))
    }

    @Test
    fun `display name wins over the uri`() {
        assertEquals(
            "holiday.jpg",
            InboundShareDecision.fileName("holiday.jpg", "content://x/y/123"),
        )
    }

    @Test
    fun `without a display name the decoded last uri segment is used`() {
        assertEquals(
            "image:123",
            InboundShareDecision.fileName(null, "content://media/document/image%3A123"),
        )
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
    fun `a long name is cut to the filesystem's 255 bytes, keeping its extension`() {
        val safe = InboundShareDecision.safeFileName("照".repeat(100) + ".jpg")

        assertEquals("照".repeat(83) + ".jpg", safe)
        assertTrue(safe.toByteArray(Charsets.UTF_8).size <= 255)
    }

    @Test
    fun `a cut never splits a character`() {
        assertEquals(
            "a" + "😀".repeat(63),
            InboundShareDecision.safeFileName("a" + "😀".repeat(70)),
        )
    }

    @Test
    fun `a name that fits is left whole`() {
        val name = "a".repeat(251) + ".jpg"

        assertEquals(name, InboundShareDecision.safeFileName(name))
    }

    @Test
    fun `an extension too long to keep is cut with the rest of the name`() {
        assertEquals(
            "a." + "b".repeat(253),
            InboundShareDecision.safeFileName("a." + "b".repeat(300)),
        )
    }

    @Test
    fun `only content from a provider outside Zuno may be read`() {
        val own = "im.zuno.chat"
        val gallery = "com.example.gallery"

        assertTrue(InboundShareDecision.mayRead("content", "$gallery.files", gallery, own))
        assertTrue(InboundShareDecision.mayRead("content", "unseen.provider", null, own))
        assertFalse(
            InboundShareDecision.mayRead("content", "im.zuno.chat.zuno_notifications", own, own),
        )
        assertFalse(InboundShareDecision.mayRead("file", null, null, own))
        assertFalse(InboundShareDecision.mayRead("android.resource", gallery, gallery, own))
        assertFalse(InboundShareDecision.mayRead("CONTENT", "$gallery.files", gallery, own))
        assertFalse(InboundShareDecision.mayRead(null, null, null, own))
    }

    @Test
    fun `a file Zuno itself shared out may come back in`() {
        val own = "im.zuno.chat"
        val shareOut = "im.zuno.chat.flutter.share_provider"

        assertTrue(InboundShareDecision.mayRead("content", shareOut, own, own))
        assertFalse(InboundShareDecision.mayRead("file", shareOut, own, own))
        assertFalse(
            InboundShareDecision.mayRead(
                "content",
                "com.example.flutter.share_provider",
                own,
                own,
            ),
        )
    }

    @Test
    fun `a provider is named the way the content resolver finds it`() {
        assertEquals(
            "im.zuno.chat.zuno_notifications",
            InboundShareDecision.providerAuthority("0@im.zuno.chat.zuno_notifications"),
        )
        assertEquals("media", InboundShareDecision.providerAuthority("media"))
        assertEquals("media", InboundShareDecision.providerAuthority("a@10@media"))
        assertNull(InboundShareDecision.providerAuthority(null))
    }

    @Test
    fun `rich shared text keeps its words`() {
        assertEquals(
            "bold words",
            InboundShareDecision.joinedText(listOf(StringBuilder("bold words"))),
        )
    }

    @Test
    fun `several shared texts are joined line by line, skipping blanks and repeats`() {
        assertEquals(
            "first\nsecond",
            InboundShareDecision.joinedText(
                listOf("first", null, "  ", StringBuilder("second"), "first"),
            ),
        )
    }

    @Test
    fun `no shared text gives nothing`() {
        assertNull(InboundShareDecision.joinedText(emptyList()))
        assertNull(InboundShareDecision.joinedText(listOf(null, " \n")))
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
            listOf(
                SharedFile("content://a/1", "a.jpg", "image/jpeg"),
                SharedFile("content://a/2", "b.bin", null),
            ),
        )!!
        assertEquals("https://example.org", payload["text"])
        val files = payload["files"] as List<*>
        assertEquals(
            mapOf("uri" to "content://a/1", "name" to "a.jpg", "mimeType" to "image/jpeg"),
            files[0],
        )
        assertEquals(
            mapOf("uri" to "content://a/2", "name" to "b.bin", "mimeType" to null),
            files[1],
        )
    }
}
