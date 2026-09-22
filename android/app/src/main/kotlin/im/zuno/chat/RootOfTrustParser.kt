package im.zuno.chat

object RootOfTrustParser {
    private const val CONTEXT_CLASS = 2
    private const val ROOT_OF_TRUST_TAG = 704
    private const val SECURITY_LEVEL_INDEX = 1
    private const val HARDWARE_ENFORCED_INDEX = 7
    private const val SOFTWARE_SECURITY_LEVEL = 0
    private const val DEVICE_LOCKED_INDEX = 1
    private const val VERIFIED_BOOT_STATE_INDEX = 2

    fun parse(extensionValue: ByteArray?): AttestedBoot? {
        if (extensionValue == null) return null
        return try {
            val wrapper = DerReader(extensionValue).readAll().single()
            val description = DerReader(wrapper.content).readAll().single().children()
            if (description[SECURITY_LEVEL_INDEX].byteValue() == SOFTWARE_SECURITY_LEVEL) {
                return null
            }
            val rootOfTrust = description[HARDWARE_ENFORCED_INDEX].children()
                .firstOrNull {
                    it.tagClass == CONTEXT_CLASS && it.tagNumber == ROOT_OF_TRUST_TAG
                }
                ?: return null
            val fields = rootOfTrust.children().single().children()
            AttestedBoot(
                deviceLocked = fields[DEVICE_LOCKED_INDEX].byteValue() != 0,
                verifiedBootState = fields[VERIFIED_BOOT_STATE_INDEX].byteValue(),
            )
        } catch (e: RuntimeException) {
            null
        }
    }

    private class DerElement(val tagClass: Int, val tagNumber: Int, val content: ByteArray) {
        fun children(): List<DerElement> = DerReader(content).readAll()

        fun byteValue(): Int = content.single().toInt() and 0xFF
    }

    private class DerReader(private val bytes: ByteArray) {
        private var position = 0

        fun readAll(): List<DerElement> {
            val elements = mutableListOf<DerElement>()
            while (position < bytes.size) elements += read()
            return elements
        }

        private fun read(): DerElement {
            val first = nextByte()
            var number = first and 0x1F
            if (number == 0x1F) {
                number = 0
                do {
                    val next = nextByte()
                    number = (number shl 7) or (next and 0x7F)
                } while (next and 0x80 != 0)
            }
            val length = readLength()
            require(length >= 0 && length <= bytes.size - position)
            val content = bytes.copyOfRange(position, position + length)
            position += length
            return DerElement(first ushr 6, number, content)
        }

        private fun readLength(): Int {
            val first = nextByte()
            if (first < 0x80) return first
            val count = first and 0x7F
            require(count in 1..3)
            var length = 0
            repeat(count) { length = (length shl 8) or nextByte() }
            return length
        }

        private fun nextByte(): Int {
            require(position < bytes.size)
            return bytes[position++].toInt() and 0xFF
        }
    }
}
