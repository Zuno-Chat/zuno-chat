package im.zuno.chat

import im.zuno.chat.RingBlobFixture.EXPIRY
import im.zuno.chat.RingBlobFixture.KID
import im.zuno.chat.RingBlobFixture.header
import im.zuno.chat.RingBlobFixture.ring
import im.zuno.chat.RingBlobOpen.Forged
import im.zuno.chat.RingBlobOpen.Opened
import im.zuno.chat.RingBlobOpen.UnknownKid
import im.zuno.chat.RingBlobOpen.UnknownVersion
import im.zuno.chat.RingPushOutcome.Drop
import im.zuno.chat.RingPushOutcome.ReRegister
import im.zuno.chat.RingPushOutcome.Ring
import org.junit.Assert.assertEquals
import org.junit.Test

class RingPushDecisionTest {
    private val opened = Opened(header, ring)

    private fun decide(
        blob: RingBlobOpen = opened,
        now: Long = 1_790_000_001_000,
        offset: Long? = 0,
    ) = RingPushDecision.decide(blob, nowMs = now, serverOffsetMs = offset)

    @Test
    fun `a fresh ring rings with what it carries, until its expiry and five seconds more`() {
        assertEquals(Ring(ring, ringMs = 49_000), decide())
    }

    @Test
    fun `a ring still rings at its expiry and is stale a moment after`() {
        assertEquals(Ring(ring, ringMs = 5_000), decide(now = 1_790_000_045_000))
        assertEquals(Drop(RingDropReason.STALE), decide(now = 1_790_000_045_001))
        assertEquals(Drop(RingDropReason.STALE), decide(now = 1_790_000_046_000))
    }

    @Test
    fun `the server clock decides staleness, not the device clock`() {
        assertEquals(Drop(RingDropReason.STALE), decide(now = 1_790_000_001_000, offset = 50_000))
        assertEquals(Ring(ring, ringMs = 10_000), decide(now = 1_790_000_090_000, offset = -50_000))
    }

    @Test
    fun `without a server offset the device clock gets sixty seconds`() {
        assertEquals(Ring(ring, ringMs = 5_000), decide(now = 1_790_000_105_000, offset = null))
        assertEquals(Drop(RingDropReason.STALE), decide(now = 1_790_000_105_001, offset = null))
    }

    @Test
    fun `the server clock decides how long a ring rings`() {
        assertEquals(Ring(ring, ringMs = 39_000), decide(offset = 10_000))
        assertEquals(Ring(ring, ringMs = 49_000), decide(offset = null))
    }

    @Test
    fun `a ring that arrives before it was sent rings from its send time`() {
        assertEquals(Ring(ring, ringMs = 50_000), decide(now = 1_789_999_980_000))
    }

    @Test
    fun `a ring never rings longer than the ring timeout`() {
        val distant = Opened(RingBlobHeader(KID, EXPIRY + 600), ring)

        assertEquals(Ring(ring, ringMs = 60_000), decide(distant))
    }

    @Test
    fun `a send time past the expiry is stale even on a clock that runs behind`() {
        val skewed = RingBlobFixture.opened("skewed_sender")
        val receivedAt = RingBlobFixture.vector(
            "skewed_sender",
        ).getJSONObject("payload").getLong("rts")

        assertEquals(Drop(RingDropReason.STALE), decide(skewed, now = receivedAt, offset = 0))
        assertEquals(Drop(RingDropReason.STALE), decide(skewed, now = receivedAt, offset = null))
    }

    @Test
    fun `a forged ring is dropped`() {
        assertEquals(Drop(RingDropReason.FORGED), decide(Forged))
    }

    @Test
    fun `an unknown kid asks to register again`() {
        assertEquals(ReRegister, decide(UnknownKid(header)))
        assertEquals(ReRegister, decide(UnknownKid(header), offset = null))
    }

    @Test
    fun `a stale unknown kid is dropped without registering again`() {
        assertEquals(
            Drop(RingDropReason.STALE),
            decide(UnknownKid(header), now = 1_790_000_046_000),
        )
        assertEquals(
            Drop(RingDropReason.STALE),
            decide(UnknownKid(header), now = 1_790_000_106_000, offset = null),
        )
    }

    @Test
    fun `an unknown version asks to register again whatever the time`() {
        assertEquals(ReRegister, decide(UnknownVersion))
        assertEquals(
            ReRegister,
            decide(UnknownVersion, now = Long.MAX_VALUE),
        )
    }

    @Test
    fun `every contract vector rings at its send time and every tamper case has its outcome`() {
        for (vector in RingBlobFixture.vectors().filter {
            it.getString("name") != "skewed_sender"
        }) {
            val name = vector.getString("name")
            val sentAt = vector.getJSONObject("payload").getLong("ts")
            val outcome = decide(RingBlobFixture.opened(name), now = sentAt)

            assertEquals(name, Ring::class, outcome::class)
        }
        for (tamper in RingBlobFixture.tamper()) {
            val name = tamper.getString("name")
            val blob = RingBlob.open(mapOf("z" to tamper.getString("blob")), RingBlobFixture::keys)
            val expected = when (tamper.getString("expect")) {
                "forged" -> Drop::class
                else -> ReRegister::class
            }

            assertEquals(name, expected, decide(blob)::class)
        }
    }
}
