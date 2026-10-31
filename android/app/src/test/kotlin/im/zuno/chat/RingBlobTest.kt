package im.zuno.chat

import im.zuno.chat.RingBlobFixture.endPayload
import im.zuno.chat.RingBlobFixture.header
import im.zuno.chat.RingBlobFixture.keys
import im.zuno.chat.RingBlobFixture.payload
import im.zuno.chat.RingBlobFixture.ring
import im.zuno.chat.RingBlobFixture.seal
import im.zuno.chat.RingBlobOpen.Ended
import im.zuno.chat.RingBlobOpen.Forged
import im.zuno.chat.RingBlobOpen.Opened
import im.zuno.chat.RingBlobOpen.UnknownKid
import im.zuno.chat.RingBlobOpen.UnknownVersion
import java.util.Base64
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RingBlobTest {
    private fun opened(vararg overrides: Pair<String, Any?>) =
        RingBlob.open(seal(payload(*overrides)), ::keys)

    @Test
    fun `the platform opens ChaCha20-Poly1305`() {
        assertTrue(RingBlob.isSupported)
    }

    @Test
    fun `every contract vector opens to its payload`() {
        val vectors = RingBlobFixture.vectors()
        assertEquals(
            listOf("known_answer", "long_ids", "escaped_text", "skewed_sender"),
            vectors.map { it.getString("name") },
        )
        for (vector in vectors) {
            val name = vector.getString("name")
            val payload = vector.getJSONObject("payload")
            val expected = PushedRing(
                room = payload.getString("room"),
                call = payload.getString("call"),
                caller = payload.getString("caller"),
                cname = payload.getString("cname"),
                rname = payload.getString("rname"),
                kind = RingKind.entries.single { it.wire == payload.getString("kind") },
                ts = payload.getLong("ts"),
            )

            assertEquals(
                name,
                Opened(
                    RingBlobHeader(RingBlobFixture.contract.getLong("kid"), vector.getLong("x")),
                    expected,
                ),
                RingBlob.open(RingBlobFixture.bytes(vector.getString("blob")), ::keys),
            )
        }
    }

    @Test
    fun `the known answer opens with the contract key`() {
        assertArrayEquals(
            RingBlobFixture.bytes(RingBlobFixture.contract.getString("key")),
            RingBlobFixture.key,
        )
        assertEquals(Opened(header, ring), RingBlobFixture.opened("known_answer"))
    }

    @Test
    fun `every contract tamper case has its outcome`() {
        val expected = mapOf(
            "flipped_tag" to Forged,
            "flipped_aad_byte" to Forged,
            "flipped_ciphertext_byte" to Forged,
            "truncated" to Forged,
            "short_header" to Forged,
            "unpadded_length" to Forged,
            "not_base64" to Forged,
            "unknown_version" to UnknownVersion,
            "unknown_kid" to
                UnknownKid(RingBlobHeader(RingBlobFixture.KID + 1, RingBlobFixture.EXPIRY)),
        )
        val tampered = RingBlobFixture.tamper()
        assertEquals(expected.keys, tampered.map { it.getString("name") }.toSet())

        for (tamper in tampered) {
            val name = tamper.getString("name")
            val outcome = RingBlob.open(
                mapOf("z" to tamper.getString("blob"), "event_id" to "\$z"),
                ::keys,
            )

            assertEquals(name, expected[name], outcome)
            assertEquals(name, tamper.getString("expect") == "forged", outcome == Forged)
        }
    }

    @Test
    fun `the test sealer reproduces the contract blob`() {
        assertArrayEquals(
            RingBlobFixture.bytes(RingBlobFixture.vector("known_answer").getString("blob")),
            seal(),
        )
    }

    @Test
    fun `the header is readable without a key`() {
        assertEquals(header, RingBlob.header(seal()))
        assertNull(RingBlob.header(byteArrayOf(0x02) + seal().copyOfRange(1, 549)))
        assertNull(RingBlob.header(seal().copyOf(8)))
    }

    @Test
    fun `a ciphertext of any other size is forged`() {
        assertEquals(Forged, RingBlob.open(seal(padTo = 600), ::keys))
        assertEquals(Forged, RingBlob.open(seal().copyOf(30), ::keys))
    }

    @Test
    fun `the longer padded size opens too`() {
        assertEquals(Opened(header, ring), RingBlob.open(seal(padTo = 1024), ::keys))
    }

    @Test
    fun `a blob too short for its header is forged whatever its version`() {
        assertEquals(Forged, RingBlob.open(seal().copyOf(5), ::keys))
        assertEquals(Forged, RingBlob.open(byteArrayOf(0x02, 0x00), ::keys))
        assertEquals(Forged, RingBlob.open(ByteArray(0), ::keys))
    }

    @Test
    fun `an unknown kid is reported whatever the blob length`() {
        assertEquals(UnknownKid(header), RingBlob.open(seal().copyOf(30)) { null })
        assertEquals(UnknownKid(header), RingBlob.open(seal()) { null })
    }

    @Test
    fun `a blob sealed under another key is forged`() {
        assertEquals(Forged, RingBlob.open(seal()) { ByteArray(32) { 7 } })
    }

    @Test
    fun `an authentic ring without its room, call or caller is forged`() {
        assertEquals(Forged, opened("room" to ""))
        assertEquals(Forged, opened("room" to null))
        assertEquals(Forged, opened("call" to ""))
        assertEquals(Forged, opened("call" to null))
        assertEquals(Forged, opened("caller" to ""))
        assertEquals(Forged, opened("caller" to null))
    }

    @Test
    fun `an unknown kind is forged`() {
        assertEquals(Forged, opened("kind" to "fax"))
    }

    @Test
    fun `a ring whose send time is not a number or whose text is not JSON is forged`() {
        assertEquals(Forged, opened("ts" to "1"))
        assertEquals(Forged, opened("ts" to null))
        assertEquals(Forged, RingBlob.open(seal("[1,2]"), ::keys))
        assertEquals(Forged, RingBlob.open(seal("not json"), ::keys))
    }

    @Test
    fun `missing names open as empty`() {
        assertEquals(
            Opened(header, ring.copy(cname = "", rname = "")),
            opened("cname" to null, "rname" to null),
        )
    }

    @Test
    fun `a ring opens without rts and whatever other keys it carries`() {
        assertEquals(Opened(header, ring), opened("rts" to null))
        assertEquals(Opened(header, ring), opened("v" to 2))
    }

    @Test
    fun `every end vector opens to its call and reason`() {
        val vectors = RingBlobFixture.endVectors()
        assertEquals(
            listOf("known_answer", "answered_elsewhere", "ended"),
            vectors.map { it.getString("name") },
        )
        for (vector in vectors) {
            val payload = vector.getJSONObject("payload")
            val expected = PushedRingEnd(
                room = payload.getString("room"),
                call = payload.getString("call"),
                ts = payload.getLong("ts"),
            )

            assertEquals(
                vector.getString("name"),
                Ended(
                    RingBlobHeader(RingBlobFixture.endContract.getLong("kid"), vector.getLong("x")),
                    expected,
                ),
                RingBlob.openEnd(RingBlobFixture.bytes(vector.getString("blob")), ::keys),
            )
        }
    }

    @Test
    fun `the test sealer reproduces every end vector`() {
        for (vector in RingBlobFixture.endVectors()) {
            assertArrayEquals(
                vector.getString("name"),
                RingBlobFixture.bytes(vector.getString("blob")),
                seal(
                    vector.getString("plaintext"),
                    withNonce = RingBlobFixture.bytes(vector.getString("nonce")),
                ),
            )
        }
    }

    @Test
    fun `an end ends the ring whatever reason it gives, or none`() {
        for (reason in listOf("moved_away", null)) {
            assertEquals(
                "$reason",
                Ended(header, RingBlobFixture.end),
                RingBlob.openEnd(seal(endPayload("reason" to reason)), ::keys),
            )
        }
    }

    @Test
    fun `an end without its room, call or send time is forged`() {
        for (missing in listOf("room", "call", "ts")) {
            assertEquals(missing, Forged, RingBlob.openEnd(seal(endPayload(missing to null)), ::keys))
        }
        assertEquals(Forged, RingBlob.openEnd(seal(endPayload("call" to "")), ::keys))
        assertEquals(Forged, RingBlob.openEnd(seal(endPayload("ts" to "1")), ::keys))
    }

    @Test
    fun `only the ze key carries an end, so an end sealed under z is forged`() {
        val sealed = Base64.getEncoder().encodeToString(seal(endPayload()))

        assertEquals(Forged, RingBlob.open(mapOf("z" to sealed), ::keys))
    }

    @Test
    fun `an end carried in ze opens as an end`() {
        val sealed = Base64.getEncoder().encodeToString(seal(endPayload()))

        assertEquals(Ended(header, RingBlobFixture.end), RingBlob.open(mapOf("ze" to sealed), ::keys))
    }

    @Test
    fun `a blob under ze that does not say it is an end is forged, so a ring moved there ends nothing`() {
        for (sealed in listOf(seal(endPayload("kind" to null)), seal(payload()))) {
            val carried = Base64.getEncoder().encodeToString(sealed)

            assertEquals(Forged, RingBlob.open(mapOf("ze" to carried), ::keys))
        }
    }

    @Test
    fun `an end carried in ze without its room, call or send time is forged`() {
        for (missing in listOf("room", "call", "ts")) {
            val sealed = Base64.getEncoder().encodeToString(
                seal(endPayload(missing to null)),
            )

            assertEquals(missing, Forged, RingBlob.open(mapOf("ze" to sealed), ::keys))
        }
        assertEquals(Forged, RingBlob.open(mapOf("ze" to "not base64!"), ::keys))
    }

    @Test
    fun `the push carries the blob in z`() {
        val blob = seal()

        assertArrayEquals(
            blob,
            RingBlob.bytesOf(mapOf("z" to Base64.getEncoder().encodeToString(blob))),
        )
        assertNull(RingBlob.bytesOf(mapOf("z" to "%%%")))
        assertNull(RingBlob.bytesOf(mapOf("event_id" to "\$z")))
        assertEquals(Forged, RingBlob.open(mapOf("event_id" to "\$z"), ::keys))
        assertEquals(Forged, RingBlob.open(mapOf("z" to "%%%"), ::keys))
    }
}
