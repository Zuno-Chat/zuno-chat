package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CaughtErrorsTest {
    private fun entry(label: String, message: String = "boom") =
        CaughtError(label, "java.lang.IllegalStateException", message, "at A.b(A.kt:1)")

    @Test
    fun `an entry survives a round trip`() {
        val stored = CaughtErrors.appended(null, entry("share import"))

        assertEquals(listOf(entry("share import")), CaughtErrors.parse(stored))
    }

    @Test
    fun `a label already waiting is not recorded again`() {
        val stored = CaughtErrors.appended(null, entry("share import"))

        assertNull(CaughtErrors.appended(stored, entry("share import", "again")))
    }

    @Test
    fun `only the newest entries are kept`() {
        var stored: String? = null
        for (index in 0..CaughtErrors.LIMIT) {
            stored = CaughtErrors.appended(stored, entry("label $index"))
        }

        val labels = CaughtErrors.parse(stored).map { it.label }
        assertEquals(CaughtErrors.LIMIT, labels.size)
        assertEquals("label 1", labels.first())
    }

    @Test
    fun `separator characters in a message cannot split an entry`() {
        val stored = CaughtErrors.appended(null, entry("pusher", "a\u001Eb\u001Fc"))

        assertEquals(listOf("abc"), CaughtErrors.parse(stored).map { it.message })
    }

    @Test
    fun `a throwable keeps its class, message and top frames`() {
        val error = CaughtErrors.entryFor("video probe", IllegalArgumentException("no track"))

        assertEquals("java.lang.IllegalArgumentException", error.type)
        assertEquals("no track", error.message)
        assertTrue(error.stack.lines().size <= CaughtErrors.FRAMES)
    }

    @Test
    fun `nothing stored reads as no entries`() {
        assertEquals(emptyList<CaughtError>(), CaughtErrors.parse(null))
        assertEquals(emptyList<CaughtError>(), CaughtErrors.parse(""))
    }
}
