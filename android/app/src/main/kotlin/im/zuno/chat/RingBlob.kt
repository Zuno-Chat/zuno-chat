package im.zuno.chat

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.security.GeneralSecurityException
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener

enum class RingKind(val wire: String) {
    VOICE("voice"),
    VIDEO("video"),
}

data class PushedRing(
    val room: String,
    val call: String,
    val caller: String,
    val cname: String,
    val rname: String,
    val kind: RingKind,
    val ts: Long,
)

data class RingBlobHeader(val kid: Long, val expiry: Long)

sealed interface RingBlobOpen {
    data class Opened(val header: RingBlobHeader, val ring: PushedRing) : RingBlobOpen

    data class UnknownKid(val header: RingBlobHeader) : RingBlobOpen

    data object UnknownVersion : RingBlobOpen

    data object Forged : RingBlobOpen
}

object RingBlob {
    const val PUSH_KEY = "z"
    private const val VERSION: Byte = 0x01
    private const val HEADER_LENGTH = 9
    private const val NONCE_LENGTH = 12
    private const val TAG_LENGTH = 16
    private val PADDED_LENGTHS = setOf(512, 1024)
    private val label = "zuno-voip-v1".toByteArray(Charsets.UTF_8)
    private val transformations = listOf("ChaCha20/Poly1305/NoPadding", "ChaCha20-Poly1305")

    private val transformation: String? by lazy {
        transformations.firstOrNull { name ->
            try {
                Cipher.getInstance(name)
                true
            } catch (error: GeneralSecurityException) {
                false
            }
        }
    }

    val isSupported: Boolean get() = transformation != null

    internal fun bytesOf(data: Map<String, String?>): ByteArray? {
        val encoded = data[PUSH_KEY] ?: return null
        return try {
            Base64.getDecoder().decode(encoded)
        } catch (error: IllegalArgumentException) {
            null
        }
    }

    fun open(data: Map<String, String?>, key: (Long) -> ByteArray?): RingBlobOpen {
        val blob = bytesOf(data) ?: return RingBlobOpen.Forged
        return open(blob, key)
    }

    internal fun header(blob: ByteArray): RingBlobHeader? {
        if (blob.size < HEADER_LENGTH || blob[0] != VERSION) return null
        return RingBlobHeader(kid = uint32(blob, 1), expiry = uint32(blob, 5))
    }

    internal fun open(blob: ByteArray, key: (Long) -> ByteArray?): RingBlobOpen {
        if (blob.size < HEADER_LENGTH) return RingBlobOpen.Forged
        val header = header(blob) ?: return RingBlobOpen.UnknownVersion
        val secret = key(header.kid) ?: return RingBlobOpen.UnknownKid(header)
        if (blob.size - HEADER_LENGTH - NONCE_LENGTH - TAG_LENGTH !in PADDED_LENGTHS) {
            return RingBlobOpen.Forged
        }
        val plaintext = decrypt(blob, secret) ?: return RingBlobOpen.Forged
        val ring = ringOf(plaintext) ?: return RingBlobOpen.Forged
        return RingBlobOpen.Opened(header, ring)
    }

    private fun decrypt(blob: ByteArray, secret: ByteArray): ByteArray? {
        val name = transformation ?: return null
        return try {
            val cipher = Cipher.getInstance(name)
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(secret, "ChaCha20"),
                IvParameterSpec(blob, HEADER_LENGTH, NONCE_LENGTH),
            )
            cipher.updateAAD(label + blob.copyOfRange(0, HEADER_LENGTH))
            cipher.doFinal(
                blob,
                HEADER_LENGTH + NONCE_LENGTH,
                blob.size - HEADER_LENGTH - NONCE_LENGTH,
            )
        } catch (error: GeneralSecurityException) {
            null
        } catch (error: IllegalArgumentException) {
            null
        }
    }

    private fun ringOf(plaintext: ByteArray): PushedRing? {
        var end = plaintext.size
        while (end > 0 && plaintext[end - 1] == 0.toByte()) end--
        val text = try {
            Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(plaintext, 0, end)).toString()
        } catch (error: CharacterCodingException) {
            return null
        }
        val json = try {
            JSONTokener(text).nextValue() as? JSONObject
        } catch (error: JSONException) {
            null
        } ?: return null
        val room = (json.opt("room") as? String)?.takeIf { it.isNotEmpty() } ?: return null
        val call = (json.opt("call") as? String)?.takeIf { it.isNotEmpty() } ?: return null
        val caller = (json.opt("caller") as? String)?.takeIf { it.isNotEmpty() } ?: return null
        val kind = RingKind.entries.firstOrNull { it.wire == json.opt("kind") } ?: return null
        val ts = (json.opt("ts") as? Number)?.toLong() ?: return null
        return PushedRing(
            room = room,
            call = call,
            caller = caller,
            cname = json.opt("cname") as? String ?: "",
            rname = json.opt("rname") as? String ?: "",
            kind = kind,
            ts = ts,
        )
    }

    private fun uint32(bytes: ByteArray, offset: Int): Long =
        (offset until offset + 4).fold(0L) { value, index ->
            (value shl 8) or
                (bytes[index].toLong() and 0xFF)
        }
}
