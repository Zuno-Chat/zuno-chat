package im.zuno.chat

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.security.GeneralSecurityException
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import im.zuno.chat.zuno_notifications.PushKind
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

data class PushedRingEnd(val room: String, val call: String, val ts: Long)

data class RingBlobHeader(val kid: Long, val expiry: Long)

sealed interface RingBlobOpen {
    data class Opened(val header: RingBlobHeader, val ring: PushedRing) : RingBlobOpen

    data class Ended(val header: RingBlobHeader, val end: PushedRingEnd) : RingBlobOpen

    data class UnknownKid(val header: RingBlobHeader) : RingBlobOpen

    data object UnknownVersion : RingBlobOpen

    data object Forged : RingBlobOpen
}

object RingBlob {
    const val PUSH_KEY = "z"
    const val END_PUSH_KEY = "ze"
    private const val END_KIND = "end"
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

    fun pushKind(eventId: String?, roomId: String?, data: Map<String, String?>): PushKind =
        PushKind.of(
            eventId,
            roomId,
            ring = data[PUSH_KEY] != null,
            ringEnd = data[END_PUSH_KEY] != null,
        )

    internal fun bytesOf(data: Map<String, String?>): ByteArray? = data[PUSH_KEY]?.let(::decoded)

    fun open(data: Map<String, String?>, key: (Long) -> ByteArray?): RingBlobOpen {
        data[END_PUSH_KEY]?.let { sealed ->
            return openEnd(decoded(sealed) ?: return RingBlobOpen.Forged, key)
        }
        val blob = bytesOf(data) ?: return RingBlobOpen.Forged
        return open(blob, key)
    }

    private fun decoded(encoded: String): ByteArray? = try {
        Base64.getDecoder().decode(encoded)
    } catch (error: IllegalArgumentException) {
        null
    }

    internal fun header(blob: ByteArray): RingBlobHeader? {
        if (blob.size < HEADER_LENGTH || blob[0] != VERSION) return null
        return RingBlobHeader(kid = uint32(blob, 1), expiry = uint32(blob, 5))
    }

    internal fun open(blob: ByteArray, key: (Long) -> ByteArray?): RingBlobOpen =
        openSealed(blob, key) { header, json ->
            ringOf(json)?.let { RingBlobOpen.Opened(header, it) }
        }

    internal fun openEnd(blob: ByteArray, key: (Long) -> ByteArray?): RingBlobOpen =
        openSealed(blob, key) { header, json ->
            endOf(json)?.let { RingBlobOpen.Ended(header, it) }
        }

    private fun openSealed(
        blob: ByteArray,
        key: (Long) -> ByteArray?,
        payload: (RingBlobHeader, JSONObject) -> RingBlobOpen?,
    ): RingBlobOpen {
        if (blob.size < HEADER_LENGTH) return RingBlobOpen.Forged
        val header = header(blob) ?: return RingBlobOpen.UnknownVersion
        val secret = key(header.kid) ?: return RingBlobOpen.UnknownKid(header)
        if (blob.size - HEADER_LENGTH - NONCE_LENGTH - TAG_LENGTH !in PADDED_LENGTHS) {
            return RingBlobOpen.Forged
        }
        val plaintext = decrypt(blob, secret) ?: return RingBlobOpen.Forged
        val json = jsonOf(plaintext) ?: return RingBlobOpen.Forged
        return payload(header, json) ?: RingBlobOpen.Forged
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

    private fun jsonOf(plaintext: ByteArray): JSONObject? {
        var end = plaintext.size
        while (end > 0 && plaintext[end - 1] == 0.toByte()) end--
        val text = try {
            Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(plaintext, 0, end)).toString()
        } catch (error: CharacterCodingException) {
            return null
        }
        return try {
            JSONTokener(text).nextValue() as? JSONObject
        } catch (error: JSONException) {
            null
        }
    }

    private fun JSONObject.text(name: String): String? =
        (opt(name) as? String)?.takeIf { it.isNotEmpty() }

    private fun JSONObject.sentAt(): Long? = (opt("ts") as? Number)?.toLong()

    private fun endOf(json: JSONObject): PushedRingEnd? {
        if (json.opt("kind") != END_KIND) return null
        return PushedRingEnd(
            room = json.text("room") ?: return null,
            call = json.text("call") ?: return null,
            ts = json.sentAt() ?: return null,
        )
    }

    private fun ringOf(json: JSONObject): PushedRing? {
        val room = json.text("room") ?: return null
        val call = json.text("call") ?: return null
        val caller = json.text("caller") ?: return null
        val kind = RingKind.entries.firstOrNull { it.wire == json.opt("kind") } ?: return null
        val ts = json.sentAt() ?: return null
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
