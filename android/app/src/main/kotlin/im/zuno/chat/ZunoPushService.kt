package im.zuno.chat

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import im.zuno.chat.zuno_notifications.PushKind
import im.zuno.chat.zuno_notifications.PushNotice
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.unifiedpush.android.connector.data.PushMessage
import org.unifiedpush.flutter.connector.Plugin
import org.unifiedpush.flutter.connector.UnifiedPushService

class ZunoPushService : UnifiedPushService() {
    override fun getEngine(context: Context): FlutterEngine {
        extendWakeLock(context)
        return PushEnginePlugins.create(context).apply {
            MethodChannel(dartExecutor.binaryMessenger, WAKELOCK_CHANNEL)
                .setMethodCallHandler(wakeLockHandler(context))
            localizationPlugin.sendLocalesToFlutter(context.resources.configuration)
            dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
                listOf("--unifiedpush-bg"),
            )
        }
    }

    override fun onCreate() {
        ensureDeliveryEngine()
        super.onCreate()
    }

    @Synchronized
    private fun ensureDeliveryEngine() {
        val action = PushEngineDecision.decide(
            appEngineAlive = AppEngine.alive,
            headlessEngineGeneration = headlessEngineGeneration,
            pluginCount = Plugin.count,
        )
        when (action) {
            PushEngineAction.UseExistingAppEngine,
            PushEngineAction.ReuseHeadlessEngine,
            -> return

            PushEngineAction.ReplaceHeadlessEngine -> {
                val superseded = headlessEngine
                headlessEngine = null
                headlessEngineGeneration = null
                bootHeadlessEngine()
                superseded?.let { retire(it, attempt = 0) }
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
        val notification = notificationOf(message)
        val eventId = notification?.optString("event_id")?.ifEmpty { null }
        val roomId = notification?.optString("room_id")?.ifEmpty { null }
        when (PushKind.of(eventId, roomId)) {
            PushKind.TEST -> {
                PushNotice.postTest(applicationContext)
                return
            }

            PushKind.MESSAGE -> PushNotice.post(applicationContext, roomId, eventId)

            PushKind.BADGE -> Unit
        }
        val hold = PushEngineDecision.shouldHoldWakeLock(
            appEngineAlive = AppEngine.alive,
            hasHeadlessEngine = headlessEngine != null,
        )
        if (hold) holdWakeLock(applicationContext, eventId)
        super.onMessage(message, instance)
    }

    private fun notificationOf(message: PushMessage): JSONObject? = try {
        val json = JSONObject(String(message.content, Charsets.UTF_8))
        json.optJSONObject("notification") ?: json
    } catch (e: Exception) {
        Log.d(TAG, "No instant notice for this push: ${e.message}")
        null
    }

    internal companion object {
        const val TAG = "ZunoPushService"
        const val WAKELOCK_CHANNEL = "zuno/push_wakelock"
        const val WAKELOCK_TAG = "zuno:push"

        const val WAKELOCK_TIMEOUT_MS = 30_000L
        private const val WAKELOCK_WRITE_OFF_MS = 300_000L

        private const val MAX_RETIRE_ATTEMPTS = 20
        private const val RETIRE_RETRY_MS = 30_000L
        private val main = Handler(Looper.getMainLooper())

        private var wakeLock: PowerManager.WakeLock? = null
        private val holds = PushHolds(WAKELOCK_TIMEOUT_MS, WAKELOCK_WRITE_OFF_MS)

        fun retire(engine: FlutterEngine, attempt: Int) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, WAKELOCK_CHANNEL)
            EngineQuiescence.ask(channel, main) { quiet ->
                when {
                    quiet -> try {
                        engine.destroy()
                        Log.d(TAG, "Superseded headless engine destroyed")
                    } catch (e: Exception) {
                        Log.w(TAG, "Could not destroy the superseded headless engine", e)
                    }

                    attempt + 1 < MAX_RETIRE_ATTEMPTS -> main.postDelayed(
                        { retire(engine, attempt + 1) },
                        RETIRE_RETRY_MS,
                    )

                    else -> Log.w(
                        TAG,
                        "Superseded headless engine never went quiet; leaving it running",
                    )
                }
            }
        }

        @Synchronized
        fun holdWakeLock(context: Context, key: String?) {
            holds.acquire(key, SystemClock.elapsedRealtime())
            extendWakeLock(context)
        }

        @Synchronized
        fun extendWakeLock(context: Context) {
            try {
                wakeLock(context).acquire(WAKELOCK_TIMEOUT_MS)
            } catch (e: Exception) {
                Log.w(TAG, "Could not take a push wakelock", e)
            }
        }

        @Synchronized
        fun releaseWakeLock(key: String?) {
            if (!holds.release(key, SystemClock.elapsedRealtime())) return
            try {
                wakeLock?.takeIf { it.isHeld }?.release()
            } catch (e: Exception) {
                Log.w(TAG, "Could not release the push wakelock", e)
            }
        }

        fun wakeLockHandler(context: Context) = MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "release" -> {
                    releaseWakeLock(call.argument<String>("key"))
                    result.success(null)
                }

                "appInFront" -> result.success(
                    PushNotice.appInFront(context.applicationContext),
                )

                else -> result.notImplemented()
            }
        }

        private fun wakeLock(context: Context): PowerManager.WakeLock = wakeLock
            ?: (context.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG)
                .apply { setReferenceCounted(false) }
                .also { wakeLock = it }

        @Volatile
        var headlessEngine: FlutterEngine? = null

        @Volatile
        var headlessEngineGeneration: Int? = null
    }
}
