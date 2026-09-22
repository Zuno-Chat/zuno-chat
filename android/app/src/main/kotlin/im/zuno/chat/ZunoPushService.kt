package im.zuno.chat

import android.content.Context
import android.os.PowerManager
import android.util.Log
import im.zuno.chat.zuno_notifications.PushNotice
import im.zuno.chat.zuno_notifications.PushNoticeDecision
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.unifiedpush.android.connector.data.PushMessage
import org.unifiedpush.flutter.connector.Plugin
import org.unifiedpush.flutter.connector.UnifiedPushService

class ZunoPushService : UnifiedPushService() {
    @Volatile
    private var bootedForThisPush = false

    override fun getEngine(context: Context): FlutterEngine {
        acquireWakeLock()
        return FlutterEngine(context).apply {
            MethodChannel(dartExecutor.binaryMessenger, WAKELOCK_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "release" -> {
                            releaseWakeLock()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            localizationPlugin.sendLocalesToFlutter(context.resources.configuration)
            dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
                listOf("--unifiedpush-bg"),
            )
        }
    }

    override fun onCreate() {
        bootedForThisPush = PushNotice.liveEngines.get() == 0
        ensureDeliveryEngine()
        super.onCreate()
    }

    @Synchronized
    private fun ensureDeliveryEngine() {
        val action = PushEngineDecision.decide(
            appEngineAlive = appEngineAlive,
            headlessEngineGeneration = headlessEngineGeneration,
            pluginCount = Plugin.count,
        )
        when (action) {
            PushEngineAction.UseExistingAppEngine,
            PushEngineAction.ReuseHeadlessEngine,
            -> return
            PushEngineAction.ReplaceHeadlessEngine -> {
                try {
                    headlessEngine?.destroy()
                } catch (e: Exception) {
                    Log.w(TAG, "Could not destroy the superseded headless engine", e)
                }
                headlessEngine = null
                headlessEngineGeneration = null
                bootHeadlessEngine()
            }
            PushEngineAction.BootHeadlessEngine -> bootHeadlessEngine()
        }
    }

    private fun bootHeadlessEngine() {
        val engine = getEngine(this)
        val registry = engine.plugins
        (registry.get(Plugin::class.java) as? Plugin) ?: Plugin().also { registry.add(it) }
        headlessEngine = engine
        headlessEngineGeneration = Plugin.count
    }

    override fun onMessage(message: PushMessage, instance: String) {
        postInstantNotice(message)
        val ours = PushEngineDecision.shouldHoldWakeLock(
            appEngineAlive = appEngineAlive,
            hasHeadlessEngine = headlessEngine != null,
        )
        if (ours) acquireWakeLock()
        super.onMessage(message, instance)
    }

    private fun postInstantNotice(message: PushMessage) {
        try {
            val json = JSONObject(String(message.content, Charsets.UTF_8))
            val notification = json.optJSONObject("notification") ?: json
            val engines = PushNoticeDecision.enginesFor(
                bootedForThisPush = bootedForThisPush,
                liveEngines = PushNotice.liveEngines.get(),
            )
            bootedForThisPush = false
            PushNotice.post(
                applicationContext,
                notification.optString("room_id").ifEmpty { null },
                notification.optString("event_id").ifEmpty { null },
                engines,
            )
        } catch (e: Exception) {
            Log.d(TAG, "No instant notice for this push: ${e.message}")
        }
    }

    @Synchronized
    private fun acquireWakeLock() {
        try {
            val existing = wakeLock
            if (existing != null && existing.isHeld) existing.release()
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock =
                powerManager
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG)
                    .apply {
                        setReferenceCounted(false)
                        acquire(WAKELOCK_TIMEOUT_MS)
                    }
        } catch (e: Exception) {
            Log.w(TAG, "Could not take a push wakelock", e)
        }
    }

    @Synchronized
    private fun releaseWakeLock() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Could not release the push wakelock", e)
        } finally {
            wakeLock = null
        }
    }

    internal companion object {
        const val TAG = "ZunoPushService"
        const val WAKELOCK_CHANNEL = "zuno/push_wakelock"
        const val WAKELOCK_TAG = "zuno:push"

        const val WAKELOCK_TIMEOUT_MS = 30_000L

        @Volatile
        var wakeLock: PowerManager.WakeLock? = null

        @Volatile
        var headlessEngine: FlutterEngine? = null

        @Volatile
        var headlessEngineGeneration: Int? = null

        @Volatile
        var appEngineAlive = false
    }
}
