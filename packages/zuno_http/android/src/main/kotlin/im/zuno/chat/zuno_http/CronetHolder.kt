package im.zuno.chat.zuno_http

import android.content.Context
import android.util.Log
import java.util.concurrent.CompletableFuture
import java.util.concurrent.atomic.AtomicBoolean
import org.chromium.net.ConnectionMigrationOptions
import org.chromium.net.CronetEngine
import org.chromium.net.CronetProvider
import org.chromium.net.DnsOptions
import org.chromium.net.QuicOptions

object CronetHolder {
    private val started = AtomicBoolean(false)

    val engine = CompletableFuture<CronetEngine>()

    fun warmUp(context: Context) {
        if (!started.compareAndSet(false, true)) return
        val application = context.applicationContext
        Thread({ build(application) }, "zuno-cronet-init").apply { isDaemon = true }.start()
    }

    private fun build(context: Context) {
        try {
            val providers = CronetProvider.getAllProviders(context)
            val chosen = chooseBundled(providers.map { ProviderInfo(it.name, it.isEnabled) })
                ?: throw IllegalStateException("The bundled Cronet provider is unavailable")
            val provider = providers.first { it.name == chosen.name }
            val built = provider.createBuilder()
                .enableHttp2(true)
                .enableQuic(true)
                .enableBrotli(true)
                .enableHttpCache(CronetEngine.Builder.HTTP_CACHE_DISABLED, 0)
                .setQuicOptions(quicSettings())
                .setDnsOptions(DnsOptions.builder().useBuiltInDnsResolver(false).build())
                .setConnectionMigrationOptions(
                    ConnectionMigrationOptions.builder()
                        .enableDefaultNetworkMigration(true)
                        .enablePathDegradationMigration(true)
                        .allowNonDefaultNetworkUsage(true)
                        .build(),
                )
                .build()
            Log.i(TAG, "Cronet ${built.versionString}")
            engine.complete(built)
        } catch (error: Throwable) {
            Log.e(TAG, "Cronet failed to start", error)
            engine.completeExceptionally(error)
        }
    }
}

internal fun quicSettings(): QuicOptions = QuicOptions.builder().enableTlsZeroRtt(false).build()

internal const val TAG = "zuno/http"
