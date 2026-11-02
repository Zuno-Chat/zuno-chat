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

    private fun format(channels: Int = 1, rate: Int = 8_000, bits: Int = 16, encoding: Int = 1) =
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

    private fun data(vararg samples: Int) = chunk(
        "data",
        ByteBuffer.allocate(samples.size * Short.SIZE_BYTES).order(ByteOrder.LITTLE_ENDIAN)
            .apply { samples.forEach { putShort(it.toShort()) } }
            .array(),
    )

    private fun wave(vararg chunks: ByteArray): ByteArray {
        val body = ByteArrayOutputStream().apply {
            write("WAVE".toByteArray())
            chunks.forEach { write(it) }
        }.toByteArray()
        return chunk("RIFF", body)
    }

    @Test
    fun `decodes the rate and samples of a 16-bit mono tone`() {
        val tone = CallToneWave.parse(
            wave(format(rate = 8_000), data(0, 1, -1, 32_767, -32_768, 1_234)),
        )

        assertEquals(8_000, tone.sampleRate)
        assertArrayEquals(shortArrayOf(0, 1, -1, 32_767, -32_768, 1_234), tone.samples)
    }

    @Test
    fun `skips chunks it does not need before the samples`() {
        val tone = CallToneWave.parse(
            wave(format(), chunk("LIST", byteArrayOf(1, 2, 3)), data(5, -5)),
        )

        assertArrayEquals(shortArrayOf(5, -5), tone.samples)
    }

    @Test
    fun `refuses anything but 16-bit mono PCM`() {
        assertThrows(IllegalArgumentException::class.java) {
            CallToneWave.parse(wave(format(channels = 2), data(0, 0)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            CallToneWave.parse(wave(format(bits = 8), data(0, 0)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            CallToneWave.parse(wave(format(encoding = 7, bits = 8), data(0, 0)))
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
            CallToneWave.parse(wave(data(0, 0)))
        }
    }
}
