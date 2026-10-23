package im.zuno.chat

import java.nio.ByteBuffer
import java.nio.ByteOrder

class CallToneWave(val sampleRate: Int, val samples: ShortArray) {
    companion object {
        private const val PCM = 1

        fun parse(bytes: ByteArray): CallToneWave {
            val wave = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            require(bytes.size >= 12 && id(bytes, 0) == "RIFF" && id(bytes, 8) == "WAVE") {
                "not a WAV file"
            }
            var sampleRate: Int? = null
            var offset = 12
            while (offset + 8 <= bytes.size) {
                val size = wave.getInt(offset + 4)
                val body = offset + 8
                when (id(bytes, offset)) {
                    "fmt " -> {
                        require(
                            wave.getShort(body).toInt() == PCM &&
                                wave.getShort(body + 2).toInt() == 1 &&
                                wave.getShort(body + 14).toInt() == 16,
                        ) { "not 16-bit mono PCM" }
                        sampleRate = wave.getInt(body + 4)
                    }

                    "data" -> {
                        val rate = requireNotNull(sampleRate) { "samples before the format" }
                        require(size >= 0 && body + size <= bytes.size) { "truncated samples" }
                        val samples = ShortArray(size / 2)
                        wave.position(body)
                        wave.asShortBuffer().get(samples)
                        return CallToneWave(rate, samples)
                    }
                }
                offset = body + size + size % 2
            }
            throw IllegalArgumentException("no samples")
        }

        private fun id(bytes: ByteArray, offset: Int) = String(bytes, offset, 4, Charsets.US_ASCII)
    }
}
