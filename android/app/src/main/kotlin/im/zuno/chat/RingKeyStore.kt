package im.zuno.chat

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONException
import org.json.JSONObject

class RingKeys(
    val kid: Long,
    val key: ByteArray,
    val prevKid: Long? = null,
    val prevKey: ByteArray? = null,
    val prevUntilMs: Long? = null,
) {
    fun keyFor(kid: Long, nowMs: Long): ByteArray? {
        if (kid == this.kid) return key
        if (kid != prevKid || prevKey == null ||
            (prevUntilMs ?: Long.MAX_VALUE) <= nowMs
        ) {
            return null
        }
        return prevKey
    }

    fun withPreviousUntil(untilMs: Long): RingKeys = RingKeys(
        kid = kid,
        key = key,
        prevKid = prevKid,
        prevKey = prevKey,
        prevUntilMs = untilMs,
    )
}

sealed interface RingKeysRead {
    data class Ready(val keys: RingKeys) : RingKeysRead

    data object Missing : RingKeysRead

    data object Unavailable : RingKeysRead
}

sealed interface RingVaultRead {
    class Found(val bytes: ByteArray) : RingVaultRead

    data object Missing : RingVaultRead

    data object Failed : RingVaultRead
}

interface RingKeyVault {
    fun read(): RingVaultRead

    fun write(bytes: ByteArray): Boolean

    fun delete(): Boolean
}

class RingKeyStore(
    private val vault: RingKeyVault,
    private val newKid: () -> Long = { random.nextInt().toLong() and 0xFFFF_FFFFL },
    private val newKey: () -> ByteArray = { ByteArray(KEY_LENGTH).also(random::nextBytes) },
) {
    companion object {
        const val KEY_LENGTH = 32
        const val PREVIOUS_KEY_GRACE_MS = 24 * 60 * 60 * 1000L
        private val random = SecureRandom()
    }

    fun load(): RingKeysRead = when (val read = vault.read()) {
        is RingVaultRead.Found -> decode(read.bytes)?.let { RingKeysRead.Ready(it) }
            ?: RingKeysRead.Unavailable

        RingVaultRead.Missing -> RingKeysRead.Missing

        RingVaultRead.Failed -> RingKeysRead.Unavailable
    }

    fun current(): RingKeysRead = when (val read = load()) {
        is RingKeysRead.Ready -> read

        RingKeysRead.Missing -> fresh()

        RingKeysRead.Unavailable -> {
            vault.delete()
            fresh()
        }
    }

    fun rotate(): RingKeys? {
        val old = (current() as? RingKeysRead.Ready)?.keys ?: return null
        val keys =
            RingKeys(
                kid = freshKid(avoiding = old.kid),
                key = newKey(),
                prevKid = old.kid,
                prevKey = old.key,
            )
        return keys.takeIf { save(it) }
    }

    fun acknowledge(kid: Long, nowMs: Long): RingKeys? {
        val keys = (load() as? RingKeysRead.Ready)?.keys?.takeIf { it.kid == kid } ?: return null
        if (keys.prevKid == null || keys.prevUntilMs != null) return keys
        return keys.withPreviousUntil(nowMs + PREVIOUS_KEY_GRACE_MS).takeIf { save(it) }
    }

    fun delete(): Boolean = vault.delete()

    private fun fresh(): RingKeysRead {
        val keys = RingKeys(kid = freshKid(avoiding = null), key = newKey())
        return if (save(keys)) RingKeysRead.Ready(keys) else RingKeysRead.Unavailable
    }

    private fun save(keys: RingKeys): Boolean = vault.write(encode(keys))

    private fun freshKid(avoiding: Long?): Long {
        var kid = newKid()
        while (kid == 0L || kid == avoiding) kid = newKid()
        return kid
    }

    private fun encode(keys: RingKeys): ByteArray = JSONObject().apply {
        put("kid", keys.kid)
        put("key", Base64.getEncoder().encodeToString(keys.key))
        keys.prevKid?.let { put("prev_kid", it) }
        keys.prevKey?.let { put("prev_key", Base64.getEncoder().encodeToString(it)) }
        keys.prevUntilMs?.let { put("prev_until_ms", it) }
    }.toString().toByteArray(Charsets.UTF_8)

    private fun decode(bytes: ByteArray): RingKeys? = try {
        val json = JSONObject(String(bytes, Charsets.UTF_8))
        RingKeys(
            kid = json.getLong("kid"),
            key = Base64.getDecoder().decode(json.getString("key")),
            prevKid = if (json.has("prev_kid")) json.getLong("prev_kid") else null,
            prevKey = if (json.has("prev_key")) {
                Base64.getDecoder().decode(json.getString("prev_key"))
            } else {
                null
            },
            prevUntilMs = if (json.has("prev_until_ms")) json.getLong("prev_until_ms") else null,
        ).takeIf { it.key.size == KEY_LENGTH }
    } catch (error: JSONException) {
        null
    } catch (error: IllegalArgumentException) {
        null
    }
}

class KeystoreRingKeyVault(context: Context) : RingKeyVault {
    private companion object {
        const val PREFERENCES = "zuno_ring_keys"
        const val SEALED = "sealed"
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "zuno_ring_key_wrap"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
        const val TAG_BITS = 128
    }

    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    override fun read(): RingVaultRead {
        val stored = preferences.getString(SEALED, null) ?: return RingVaultRead.Missing
        return try {
            val wrap = existingWrapKey() ?: return RingVaultRead.Failed
            val sealed = Base64.getDecoder().decode(stored)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, wrap, GCMParameterSpec(TAG_BITS, sealed, 0, IV_LENGTH))
            RingVaultRead.Found(cipher.doFinal(sealed, IV_LENGTH, sealed.size - IV_LENGTH))
        } catch (error: Exception) {
            CaughtErrors.record(appContext, "ring key read", error)
            RingVaultRead.Failed
        }
    }

    override fun write(bytes: ByteArray): Boolean = try {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, existingWrapKey() ?: newWrapKey())
        val sealed = cipher.iv + cipher.doFinal(bytes)
        preferences.edit().putString(SEALED, Base64.getEncoder().encodeToString(sealed)).commit()
    } catch (error: Exception) {
        CaughtErrors.record(appContext, "ring key write", error)
        false
    }

    override fun delete(): Boolean {
        try {
            val keystore = keystore()
            if (keystore.containsAlias(ALIAS)) keystore.deleteEntry(ALIAS)
        } catch (error: Exception) {
            CaughtErrors.record(appContext, "ring key wrap delete", error)
            return false
        }
        return preferences.edit().remove(SEALED).commit()
    }

    private fun keystore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun existingWrapKey(): SecretKey? = keystore().getKey(ALIAS, null) as? SecretKey

    private fun newWrapKey(): SecretKey =
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).apply {
            init(
                KeyGenParameterSpec.Builder(
                    ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build(),
            )
        }.generateKey()
}
