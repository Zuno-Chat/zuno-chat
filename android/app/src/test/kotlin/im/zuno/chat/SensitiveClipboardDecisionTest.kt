package im.zuno.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SensitiveClipboardDecisionTest {
    @Test
    fun `before Android 10 the clipboard can be read from the background`() {
        assertTrue(SensitiveClipboardDecision.canRead(sdkInt = 28, focused = false))
    }

    @Test
    fun `from Android 10 only the focused app can read the clipboard`() {
        assertFalse(SensitiveClipboardDecision.canRead(sdkInt = 29, focused = false))
        assertTrue(SensitiveClipboardDecision.canRead(sdkInt = 29, focused = true))
        assertFalse(SensitiveClipboardDecision.canRead(sdkInt = 36, focused = false))
    }

    @Test
    fun `only the text Zuno copied is cleared`() {
        assertTrue(SensitiveClipboardDecision.clears(copied = "code", current = "code"))
        assertFalse(SensitiveClipboardDecision.clears(copied = "code", current = "other"))
        assertFalse(SensitiveClipboardDecision.clears(copied = "code", current = null))
        assertFalse(SensitiveClipboardDecision.clears(copied = null, current = null))
    }
}
