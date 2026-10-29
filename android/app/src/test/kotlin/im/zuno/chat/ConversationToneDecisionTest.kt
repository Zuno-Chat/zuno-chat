package im.zuno.chat

import android.media.AudioManager
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConversationToneDecisionTest {
    @Test
    fun `plays only with the ringer on and no call`() {
        assertTrue(
            ConversationToneDecision.plays(
                AudioManager.RINGER_MODE_NORMAL,
                AudioManager.MODE_NORMAL,
            ),
        )
    }

    @Test
    fun `stays quiet on silent or vibrate`() {
        assertFalse(
            ConversationToneDecision.plays(
                AudioManager.RINGER_MODE_SILENT,
                AudioManager.MODE_NORMAL,
            ),
        )
        assertFalse(
            ConversationToneDecision.plays(
                AudioManager.RINGER_MODE_VIBRATE,
                AudioManager.MODE_NORMAL,
            ),
        )
    }

    @Test
    fun `stays quiet on any call`() {
        for (mode in listOf(
            AudioManager.MODE_IN_CALL,
            AudioManager.MODE_IN_COMMUNICATION,
            AudioManager.MODE_RINGTONE,
        )) {
            assertFalse(ConversationToneDecision.plays(AudioManager.RINGER_MODE_NORMAL, mode))
        }
    }
}
