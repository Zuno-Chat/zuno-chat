package im.zuno.chat

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CallToneWaveTest {
    private fun chunk(id: String, body: ByteArray): ByteArray =
        ByteBuffer.allocate(8 + body.size + body.size % 2).order(ByteOrder.LITTLE_ENDIAN)
            .put(id.toByteArray())
            .putInt(body.size)
            .put(body)
            .array()

    private fun format(channels: Int = 1, rate: Int = 8_000, bits: Int = 8, encoding: Int = 7) =
        chunk(
            "fmt ",
            ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN)
                .putShort(encoding.toShort())
                .putShort(channels.toShort())
                .putInt(rate)
                .putInt(rate * channels * bits / 8)
                .putShort((channels * bits / 8).toShort())
                .putShort(bits.toShort())
                .array(),
        )

    private fun data(vararg codes: Int) = chunk(
        "data",
        ByteArray(codes.size) {
            codes[it].toByte()
        },
    )

    private fun wave(vararg chunks: ByteArray): ByteArray {
        val body = ByteArrayOutputStream().apply {
            write("WAVE".toByteArray())
            chunks.forEach { write(it) }
        }.toByteArray()
        return chunk("RIFF", body)
    }

    @Test
    fun `decodes the rate and samples of a mu-law mono tone`() {
        val tone = CallToneWave.parse(
            wave(format(rate = 8_000), data(0xFF, 0x7F, 0x80, 0x00, 0xEF, 0x6F)),
        )

        assertEquals(8_000, tone.sampleRate)
        assertArrayEquals(shortArrayOf(0, 0, 32_124, -32_124, 132, -132), tone.samples)
    }

    @Test
    fun `skips chunks it does not need before the samples`() {
        val tone = CallToneWave.parse(
            wave(format(), chunk("fact", byteArrayOf(2, 0, 0, 0)), data(0xFF, 0x80)),
        )

        assertArrayEquals(shortArrayOf(0, 32_124), tone.samples)
    }

    @Test
    fun `refuses anything but 8-bit mono mu-law`() {
        assertThrows(IllegalArgumentException::class.java) {
            CallToneWave.parse(wave(format(channels = 2), data(0xFF, 0xFF)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            CallToneWave.parse(wave(format(bits = 16), data(0xFF, 0xFF)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            CallToneWave.parse(wave(format(encoding = 1, bits = 16), data(0, 0)))
        }
    }

    @Test
    fun `refuses a file that is not a WAV or has no samples`() {
        assertThrows(IllegalArgumentException::class.java) {
            CallToneWave.parse("not a sound".toByteArray())
        }
        assertThrows(IllegalArgumentException::class.java) {
            CallToneWave.parse(wave(format()))
        }
        assertThrows(IllegalArgumentException::class.java) {
            CallToneWave.parse(wave(data(0xFF, 0xFF)))
        }
    }
}
