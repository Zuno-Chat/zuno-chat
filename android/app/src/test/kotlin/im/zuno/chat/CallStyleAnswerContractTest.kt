package im.zuno.chat

import im.zuno.chat.zuno_notifications.RingAnswer
import org.junit.Assert.assertEquals
import org.junit.Test

class CallStyleAnswerContractTest {
    private val answers = ContractFixtures.load("call_style_answers_v1.json").getJSONObject("answers")

    @Test
    fun `native code answers Dart's ring request with the fixture's strings`() {
        assertEquals(
            mapOf(
                "shown" to RingAnswer.SHOWN,
                "alreadyRinging" to RingAnswer.RINGING,
                "rangHere" to RingAnswer.RANG_HERE,
                "busy" to RingAnswer.BUSY,
                "unavailable" to RingAnswer.UNAVAILABLE,
            ),
            answers.keys().asSequence().associateWith { answers.getString(it) },
        )
    }
}
