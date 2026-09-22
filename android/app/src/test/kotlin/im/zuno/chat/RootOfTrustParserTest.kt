package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RootOfTrustParserTest {
    private val trustedEnvironment = 1
    private val software = 0

    private fun der(tag: ByteArray, content: ByteArray): ByteArray {
        val length = when {
            content.size < 0x80 -> byteArrayOf(content.size.toByte())
            content.size < 0x100 -> byteArrayOf(0x81.toByte(), content.size.toByte())
            else -> byteArrayOf(
                0x82.toByte(),
                (content.size shr 8).toByte(),
                content.size.toByte(),
            )
        }
        return tag + length + content
    }

    private fun join(parts: Array<out ByteArray>) =
        parts.fold(byteArrayOf()) { joined, part -> joined + part }

    private fun sequence(vararg parts: ByteArray) = der(byteArrayOf(0x30), join(parts))

    private fun integer(value: Int) = der(byteArrayOf(0x02), byteArrayOf(value.toByte()))

    private fun enumerated(value: Int) = der(byteArrayOf(0x0A), byteArrayOf(value.toByte()))

    private fun octets(bytes: ByteArray) = der(byteArrayOf(0x04), bytes)

    private fun boolean(value: Boolean) =
        der(byteArrayOf(0x01), byteArrayOf(if (value) 0xFF.toByte() else 0))

    private fun tagged(number: Int, content: ByteArray): ByteArray {
        if (number < 31) return der(byteArrayOf((0xA0 or number).toByte()), content)
        val tag = byteArrayOf(
            0xBF.toByte(),
            (0x80 or (number shr 7)).toByte(),
            (number and 0x7F).toByte(),
        )
        return der(tag, content)
    }

    private fun rootOfTrust(deviceLocked: Boolean, verifiedBootState: Int) = tagged(
        704,
        sequence(
            octets(ByteArray(32) { 7 }),
            boolean(deviceLocked),
            enumerated(verifiedBootState),
            octets(ByteArray(32) { 9 }),
        ),
    )

    private fun extension(
        securityLevel: Int,
        hardwareEnforced: ByteArray,
        softwareEnforced: ByteArray = sequence(),
    ) = octets(
        sequence(
            integer(200),
            enumerated(securityLevel),
            integer(200),
            enumerated(securityLevel),
            octets(ByteArray(16) { 1 }),
            octets(byteArrayOf()),
            softwareEnforced,
            hardwareEnforced,
        ),
    )

    @Test
    fun `a locked verified device is read from the hardware list`() {
        val bytes = extension(
            trustedEnvironment,
            sequence(rootOfTrust(deviceLocked = true, verifiedBootState = 0)),
        )

        assertEquals(AttestedBoot(true, 0), RootOfTrustParser.parse(bytes))
    }

    @Test
    fun `an unlocked unverified device is read from the hardware list`() {
        val bytes = extension(
            trustedEnvironment,
            sequence(rootOfTrust(deviceLocked = false, verifiedBootState = 2)),
        )

        assertEquals(AttestedBoot(false, 2), RootOfTrustParser.parse(bytes))
    }

    @Test
    fun `entries before the root of trust are skipped`() {
        val bytes = extension(
            trustedEnvironment,
            sequence(
                tagged(2, integer(3)),
                tagged(702, integer(0)),
                rootOfTrust(deviceLocked = true, verifiedBootState = 1),
                tagged(705, integer(14)),
            ),
        )

        assertEquals(AttestedBoot(true, 1), RootOfTrustParser.parse(bytes))
    }

    @Test
    fun `a software attestation is not trusted`() {
        val bytes = extension(
            software,
            sequence(rootOfTrust(deviceLocked = true, verifiedBootState = 0)),
        )

        assertNull(RootOfTrustParser.parse(bytes))
    }

    @Test
    fun `a root of trust in the software list is not trusted`() {
        val bytes = extension(
            trustedEnvironment,
            hardwareEnforced = sequence(),
            softwareEnforced = sequence(rootOfTrust(deviceLocked = true, verifiedBootState = 0)),
        )

        assertNull(RootOfTrustParser.parse(bytes))
    }

    @Test
    fun `a missing extension is unknown`() {
        assertNull(RootOfTrustParser.parse(null))
    }

    @Test
    fun `truncated bytes are unknown`() {
        val bytes = extension(
            trustedEnvironment,
            sequence(rootOfTrust(deviceLocked = true, verifiedBootState = 0)),
        )

        assertNull(RootOfTrustParser.parse(bytes.copyOf(bytes.size - 5)))
    }

    @Test
    fun `garbage is unknown`() {
        assertNull(RootOfTrustParser.parse(byteArrayOf(0x04, 0x03, 0x01, 0x02, 0x03)))
    }
}
