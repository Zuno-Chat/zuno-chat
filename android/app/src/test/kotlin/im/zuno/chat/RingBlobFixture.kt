package im.zuno.chat

import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONArray
import org.json.JSONObject

object RingBlobFixture {
    const val KID = 16_909_060L
    const val EXPIRY = 1_790_000_045L
    val key = ByteArray(32) { it.toByte() }
    val header = RingBlobHeader(KID, EXPIRY)
    val ring = PushedRing(
        room = "!abc:zuno.im",
        call = "c1",
        caller = "@alice:zuno.im",
        cname = "Alice",
        rname = "",
        kind = RingKind.VIDEO,
        ts = 1_790_000_000_000,
    )
    val end = PushedRingEnd(room = "!abc:zuno.im", call = "c1", ts = 1_790_000_030_000)
    private val nonce = ByteArray(12) { (0xa0 + it).toByte() }

    val contract: JSONObject by lazy { ContractFixtures.load("voip_blob_v1.json") }

    val endContract: JSONObject by lazy { ContractFixtures.load("ring_end_blob_v1.json") }

    fun endVectors(): List<JSONObject> = objects(endContract.getJSONArray("vectors"))

    private val endPlaintext: String by lazy {
        endVectors().single { it.getString("name") == "known_answer" }.getString("plaintext")
    }

    fun endPayload(vararg overrides: Pair<String, Any?>): String = payloadOf(endPlaintext, overrides)

    fun keys(kid: Long): ByteArray? = if (kid == KID) key else null

    fun vectors(): List<JSONObject> = objects(contract.getJSONArray("vectors"))

    fun tamper(): List<JSONObject> = objects(contract.getJSONArray("tamper"))

    fun vector(name: String): JSONObject = vectors().single { it.getString("name") == name }

    fun bytes(encoded: String): ByteArray = Base64.getDecoder().decode(encoded)

    fun opened(name: String): RingBlobOpen =
        RingBlob.open(bytes(vector(name).getString("blob")), ::keys)

    val plaintext: String by lazy { vector("known_answer").getString("plaintext") }

    fun payload(vararg overrides: Pair<String, Any?>): String = payloadOf(plaintext, overrides)

    private fun payloadOf(base: String, overrides: Array<out Pair<String, Any?>>): String {
        val json = JSONObject(base)
        for ((name, value) in overrides) {
            if (value == null) json.remove(name) else json.put(name, value)
        }
        return json.toString()
    }

    fun seal(
        plaintext: String = this.plaintext,
        padTo: Int = 512,
        kid: Long = KID,
        withNonce: ByteArray = nonce,
    ): ByteArray {
        val header = byteArrayOf(0x01) + uint32(kid) + uint32(EXPIRY)
        val padded = plaintext.toByteArray(Charsets.UTF_8).copyOf(padTo)
        val cipher = Cipher.getInstance("ChaCha20-Poly1305")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(withNonce))
        cipher.updateAAD("zuno-voip-v1".toByteArray(Charsets.UTF_8) + header)
        return header + withNonce + cipher.doFinal(padded)
    }

    private fun uint32(value: Long) = ByteArray(4) { (value shr (24 - 8 * it)).toByte() }

    private fun objects(array: JSONArray): List<JSONObject> = (0 until array.length()).map {
        array.getJSONObject(it)
    }
}
