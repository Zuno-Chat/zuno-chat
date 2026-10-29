package im.zuno.chat

import java.nio.ByteBuffer
import java.nio.ByteOrder

class CallToneWave(val sampleRate: Int, val samples: ShortArray) {
    companion object {
        private const val MU_LAW = 7

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
                            wave.getShort(body).toInt() == MU_LAW &&
                                wave.getShort(body + 2).toInt() == 1 &&
                                wave.getShort(body + 14).toInt() == 8,
                        ) { "not 8-bit mono mu-law" }
                        sampleRate = wave.getInt(body + 4)
                    }

                    "data" -> {
                        val rate = requireNotNull(sampleRate) { "samples before the format" }
                        require(size >= 0 && body + size <= bytes.size) { "truncated samples" }
                        return CallToneWave(rate, ShortArray(size) { muLaw(bytes[body + it]) })
                    }
                }
                offset = body + size + size % 2
            }
            throw IllegalArgumentException("no samples")
        }

        private fun muLaw(code: Byte): Short {
            val bits = code.toInt().inv() and 0xFF
            val exponent = (bits shr 4) and 0x07
            val magnitude = ((((bits and 0x0F) shl 3) + 0x84) shl exponent) - 0x84
            return (if ((bits and 0x80) != 0) -magnitude else magnitude).toShort()
        }

        private fun id(bytes: ByteArray, offset: Int) = String(bytes, offset, 4, Charsets.US_ASCII)
    }
}
