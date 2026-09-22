package im.zuno.chat

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec

class DeviceSafety(private val context: Context) {
    fun check(): List<String> = DeviceSafetyDecision
        .decide(attestedBoot(), bootProperties(), rootSigns())
        .map { it.channelName }

    private fun attestedBoot(): AttestedBoot? = runCatching {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        val challenge = ByteArray(CHALLENGE_BYTES).also(SecureRandom()::nextBytes)
        val spec = KeyGenParameterSpec.Builder(ATTESTATION_ALIAS, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setAttestationChallenge(challenge)
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE).run {
            initialize(spec)
            generateKeyPair()
        }
        try {
            val leaf = keyStore.getCertificateChain(ATTESTATION_ALIAS)
                ?.firstOrNull() as? X509Certificate
            RootOfTrustParser.parse(leaf?.getExtensionValue(KEY_DESCRIPTION_OID))
        } finally {
            keyStore.deleteEntry(ATTESTATION_ALIAS)
        }
    }.getOrNull()

    private fun bootProperties(): BootProperties = runCatching {
        val process = Runtime.getRuntime().exec("getprop")
        val dump = process.inputStream.bufferedReader().use { it.readText() }
        process.waitFor()
        BootProperties.fromGetprop(dump)
    }.getOrDefault(BootProperties())

    private fun rootSigns(): RootSigns = RootSigns(
        suBinaryFound = suDirectories().any { File(it, "su").exists() },
        rootAppInstalled = ROOT_APPS.any(::isInstalled),
        buildTags = Build.TAGS.orEmpty(),
    )

    private fun suDirectories(): List<String> =
        System.getenv("PATH").orEmpty().split(':').filter { it.isNotEmpty() } + SU_DIRECTORIES

    private fun isInstalled(packageName: String): Boolean = try {
        context.packageManager.getPackageInfo(packageName, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val ATTESTATION_ALIAS = "zuno_device_safety_attestation"
        private const val KEY_DESCRIPTION_OID = "1.3.6.1.4.1.11129.2.1.17"
        private const val CHALLENGE_BYTES = 16

        private val ROOT_APPS = listOf(
            "com.topjohnwu.magisk",
            "me.weishu.kernelsu",
            "me.bmax.apatch",
        )

        private val SU_DIRECTORIES = listOf(
            "/system/bin",
            "/system/xbin",
            "/system/sbin",
            "/sbin",
            "/su/bin",
            "/vendor/bin",
            "/data/local",
            "/data/local/bin",
            "/data/local/xbin",
        )
    }
}
