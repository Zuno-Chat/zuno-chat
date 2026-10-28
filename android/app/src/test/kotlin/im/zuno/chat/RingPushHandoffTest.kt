package im.zuno.chat

import im.zuno.chat.RingBlobFixture.ring
import im.zuno.chat.RingPushOutcome.Drop
import im.zuno.chat.RingPushOutcome.ReRegister
import im.zuno.chat.RingPushOutcome.Ring
import org.junit.Assert.assertEquals
import org.junit.Test

class RingPushHandoffTest {
    private val handoff = RingPushHandoff()
    private val judgedAt = 1_000_000L
    private val rang = Ring(ring, ringMs = 49_000)
    private val stale = Drop(RingDropReason.STALE)

    private fun judgedAgain(): RingPushOutcome = Drop(RingDropReason.FORGED)

    private fun RingPushHandoff.takeAt(messageId: String?, nowMs: Long = judgedAt) =
        takeOrJudge(messageId, nowMs, ::judgedAgain)

    @Test
    fun `the service takes the receiver's verdict instead of judging the push again`() {
        handoff.keep("m1", rang, judgedAt)

        assertEquals(rang, handoff.takeAt("m1"))
    }

    @Test
    fun `every verdict is handed over, not just rings`() {
        handoff.keep("m1", Drop(RingDropReason.FORGED), judgedAt)
        handoff.keep("m2", ReRegister, judgedAt)

        assertEquals(Drop(RingDropReason.FORGED), handoff.takeAt("m1"))
        assertEquals(ReRegister, handoff.takeAt("m2"))
    }

    @Test
    fun `a ring taken late rings only for the time it has left`() {
        handoff.keep("m1", rang, judgedAt)
        handoff.keep("m2", rang, judgedAt)

        assertEquals(Ring(ring, ringMs = 29_000), handoff.takeAt("m1", nowMs = judgedAt + 20_000))
        assertEquals(Ring(ring, ringMs = 1), handoff.takeAt("m2", nowMs = judgedAt + 48_999))
    }

    @Test
    fun `a clock reading before the verdict never stretches the ring`() {
        handoff.keep("m1", rang, judgedAt)

        assertEquals(rang, handoff.takeAt("m1", nowMs = judgedAt - 5_000))
    }

    @Test
    fun `a ring taken once its time from the receiver's verdict has run out is stale`() {
        handoff.keep("m1", rang, judgedAt)
        handoff.keep("m2", rang, judgedAt)

        assertEquals(stale, handoff.takeAt("m1", nowMs = judgedAt + 49_000))
        assertEquals(stale, handoff.takeAt("m2", nowMs = judgedAt + 600_000))
    }

    @Test
    fun `only a ring runs out, other verdicts hold however late they are taken`() {
        handoff.keep("m1", Drop(RingDropReason.FORGED), judgedAt)
        handoff.keep("m2", ReRegister, judgedAt)

        assertEquals(Drop(RingDropReason.FORGED), handoff.takeAt("m1", nowMs = judgedAt + 600_000))
        assertEquals(ReRegister, handoff.takeAt("m2", nowMs = judgedAt + 600_000))
    }

    @Test
    fun `a verdict is taken once`() {
        handoff.keep("m1", rang, judgedAt)
        handoff.takeAt("m1")

        assertEquals(judgedAgain(), handoff.takeAt("m1"))
    }

    @Test
    fun `a ring that ran out is taken once too`() {
        handoff.keep("m1", rang, judgedAt)
        handoff.takeAt("m1", nowMs = judgedAt + 49_000)

        assertEquals(judgedAgain(), handoff.takeAt("m1", nowMs = judgedAt + 49_000))
    }

    @Test
    fun `a push the receiver never judged is judged by the service`() {
        handoff.keep("m1", rang, judgedAt)

        assertEquals(judgedAgain(), handoff.takeAt("m2"))
        assertEquals(judgedAgain(), handoff.takeAt(null))
    }

    @Test
    fun `a push without a message id is never kept`() {
        handoff.keep(null, rang, judgedAt)

        assertEquals(judgedAgain(), handoff.takeAt(null))
    }

    @Test
    fun `past its cap the oldest verdict is dropped`() {
        val small = RingPushHandoff(capacity = 2)
        small.keep("m1", rang, judgedAt)
        small.keep("m2", rang, judgedAt)
        small.keep("m3", rang, judgedAt)

        assertEquals(judgedAgain(), small.takeAt("m1"))
        assertEquals(rang, small.takeAt("m2"))
        assertEquals(rang, small.takeAt("m3"))
    }
}
