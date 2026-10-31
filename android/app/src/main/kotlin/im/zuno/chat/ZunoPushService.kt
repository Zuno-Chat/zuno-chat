package im.zuno.chat

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import im.zuno.chat.zuno_notifications.PushKind
import im.zuno.chat.zuno_notifications.PushNotice
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.Serializable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.PushService
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage
import org.unifiedpush.flutter.connector.Call
import org.unifiedpush.flutter.connector.PLUGIN_ARG_ENDPOINT_KEY_AUTH
import org.unifiedpush.flutter.connector.PLUGIN_ARG_ENDPOINT_KEY_PUBKEY
import org.unifiedpush.flutter.connector.PLUGIN_ARG_ENDPOINT_TEMP
import org.unifiedpush.flutter.connector.PLUGIN_ARG_ENDPOINT_URL
import org.unifiedpush.flutter.connector.PLUGIN_ARG_INSTANCE
import org.unifiedpush.flutter.connector.PLUGIN_ARG_MESSAGE_CONTENT
import org.unifiedpush.flutter.connector.PLUGIN_ARG_MESSAGE_DECRYPTED
import org.unifiedpush.flutter.connector.PLUGIN_ARG_REASON
import org.unifiedpush.flutter.connector.PLUGIN_CALL_MESSAGE
import org.unifiedpush.flutter.connector.PLUGIN_CALL_NEW_ENDPOINT
import org.unifiedpush.flutter.connector.PLUGIN_CALL_REGISTRATION_FAILED
import org.unifiedpush.flutter.connector.PLUGIN_CALL_TEMP_UNAVAILABLE
import org.unifiedpush.flutter.connector.PLUGIN_CALL_UNREGISTERED
import org.unifiedpush.flutter.connector.Plugin

class ZunoPushService : PushService() {
    private fun buildEngine(context: Context): FlutterEngine {
        PushWakeLock.extend(context)
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

    @Synchronized
    private fun ensureDeliveryEngine() {
        val action = PushEngineDecision.decide(
            appEngineAlive = AppEngine.alive,
            headlessEngineGeneration = headlessEngineGeneration,
            appEngineGeneration = AppEngine.generation,
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
                superseded?.let { retire(applicationContext, it, attempt = 0) }
            }

            PushEngineAction.BootHeadlessEngine -> bootHeadlessEngine()
        }
    }

    private fun bootHeadlessEngine() {
        val engine = buildEngine(this)
        val registry = engine.plugins
        (registry.get(Plugin::class.java) as? Plugin) ?: Plugin().also { registry.add(it) }
        headlessEngine = engine
        headlessEngineGeneration = AppEngine.generation
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

            PushKind.RING, PushKind.RING_END, PushKind.BADGE -> Unit
        }
        PushWakeLock.hold(applicationContext, eventId)
        deliver(
            PLUGIN_CALL_MESSAGE,
            mapOf(
                PLUGIN_ARG_INSTANCE to instance,
                PLUGIN_ARG_MESSAGE_CONTENT to message.content,
                PLUGIN_ARG_MESSAGE_DECRYPTED to message.decrypted,
            ),
        )
    }

    override fun onNewEndpoint(endpoint: PushEndpoint, instance: String) = deliver(
        PLUGIN_CALL_NEW_ENDPOINT,
        mapOf(
            PLUGIN_ARG_INSTANCE to instance,
            PLUGIN_ARG_ENDPOINT_URL to endpoint.url,
            PLUGIN_ARG_ENDPOINT_KEY_PUBKEY to endpoint.pubKeySet?.pubKey,
            PLUGIN_ARG_ENDPOINT_KEY_AUTH to endpoint.pubKeySet?.auth,
            PLUGIN_ARG_ENDPOINT_TEMP to endpoint.temporary,
        ),
    )

    override fun onRegistrationFailed(reason: FailedReason, instance: String) = deliver(
        PLUGIN_CALL_REGISTRATION_FAILED,
        mapOf(PLUGIN_ARG_INSTANCE to instance, PLUGIN_ARG_REASON to reason.name),
    )

    override fun onUnregistered(instance: String) =
        deliver(PLUGIN_CALL_UNREGISTERED, mapOf(PLUGIN_ARG_INSTANCE to instance))

    override fun onTempUnavailable(instance: String) =
        deliver(PLUGIN_CALL_TEMP_UNAVAILABLE, mapOf(PLUGIN_ARG_INSTANCE to instance))

    private fun deliver(method: String, data: Map<String, Serializable?>) {
        val run = Runnable {
            ensureDeliveryEngine()
            CoroutineScope(Plugin.dispatcher).launch { Plugin.calls.emit(Call(method, data)) }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) run.run() else main.post(run)
    }

    private fun notificationOf(message: PushMessage): JSONObject? = try {
        val json = JSONObject(String(message.content, Charsets.UTF_8))
        json.optJSONObject("notification") ?: json
    } catch (e: Exception) {
        Log.d(TAG, "No instant notice for this push: ${e.javaClass.name}")
        null
    }

    internal companion object {
        const val TAG = "ZunoPushService"
        const val WAKELOCK_CHANNEL = "zuno/push_wakelock"

        private const val MAX_RETIRE_ATTEMPTS = 20
        private const val RETIRE_RETRY_MS = 30_000L
        private val main = Handler(Looper.getMainLooper())

        fun retire(context: Context, engine: FlutterEngine, attempt: Int) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, WAKELOCK_CHANNEL)
            EngineQuiescence.ask(context, channel, main) { quiet ->
                when {
                    quiet -> try {
                        engine.destroy()
                        Log.d(TAG, "Superseded headless engine destroyed")
                    } catch (e: Exception) {
                        CaughtErrors.record(context, "unifiedpush engine destroy", e)
                    }

                    attempt + 1 < MAX_RETIRE_ATTEMPTS -> main.postDelayed(
                        { retire(context, engine, attempt + 1) },
                        RETIRE_RETRY_MS,
                    )

                    else -> Log.w(
                        TAG,
                        "Superseded headless engine never went quiet; leaving it running",
                    )
                }
            }
        }

        fun wakeLockHandler(context: Context) = MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "release" -> {
                    PushWakeLock.release(context, call.argument<String>("key"))
                    result.success(null)
                }

                "appInFront" -> result.success(
                    PushNotice.appInFront(context.applicationContext),
                )

                else -> result.notImplemented()
            }
        }

        @Volatile
        var headlessEngine: FlutterEngine? = null

        @Volatile
        var headlessEngineGeneration: Int? = null
    }
}
