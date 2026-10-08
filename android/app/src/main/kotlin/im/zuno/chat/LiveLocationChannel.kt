package im.zuno.chat

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class LiveLocationChannel private constructor(engine: FlutterEngine, context: Context) {
    private val appContext = context.applicationContext
    private val methods = MethodChannel(engine.dartExecutor.binaryMessenger, METHODS)
    private var sink: EventChannel.EventSink? = null

    init {
        methods.setMethodCallHandler(::handle)
        EventChannel(engine.dartExecutor.binaryMessenger, FIXES).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            },
        )
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)

            "setMode" -> ifOwner(result) {
                LiveLocationMode.from(call.argument<String>("mode"))
                    ?.let(LiveLocationService::setMode)
            }

            "updateNotice" -> ifOwner(result) {
                noticeFrom(call.arguments as? Map<*, *>)?.let {
                    LiveLocationService.updateNotice(appContext, it)
                }
            }

            "releaseWakeLock" -> ifOwner(result) {
                LiveLocationService.releaseWakeLock(call.argument<Int>("seq") ?: -1)
            }

            "stop" -> ifOwner(result) { stopCapture(appContext) }

            else -> result.notImplemented()
        }
    }

    private fun ifOwner(result: MethodChannel.Result, action: () -> Unit) {
        if (owner === this) action()
        result.success(null)
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val mode = LiveLocationMode.from(call.argument<String>("mode"))
        val notice = noticeFrom(call.argument<Map<*, *>>("notice"))
        if (mode == null || notice == null) {
            result.error("bad_args", "mode and notice are required", null)
            return
        }
        if (!LiveLocationService.hasPermission(appContext)) {
            result.error("denied", "location permission is missing", null)
            return
        }
        try {
            LiveLocationService.start(appContext, mode, notice)
        } catch (error: IllegalStateException) {
            result.error("start_failed", error.javaClass.simpleName, null)
            return
        } catch (error: SecurityException) {
            result.error("denied", error.javaClass.simpleName, null)
            return
        }
        owner = this
        KeptEngine.hold(EngineKeepReason.LiveLocation)
        result.success(null)
    }

    companion object {
        private const val METHODS = "zuno/live_location"
        private const val FIXES = "zuno/live_location/fixes"

        private val registered = mutableMapOf<FlutterEngine, LiveLocationChannel>()
        private var owner: LiveLocationChannel? = null

        val attached: Boolean get() = owner != null

        fun register(engine: FlutterEngine, context: Context) {
            registered.getOrPut(engine) { LiveLocationChannel(engine, context) }
        }

        fun detach(engine: FlutterEngine, context: Context) {
            val channel = registered.remove(engine) ?: return
            if (owner === channel) stopCapture(context)
        }

        fun emit(event: Map<String, Any?>): Boolean {
            val events = owner?.sink ?: return false
            events.success(event)
            return true
        }

        fun requestStop() {
            owner?.methods?.invokeMethod("stopRequested", null)
        }

        private fun stopCapture(context: Context) {
            owner = null
            LiveLocationService.stop(context)
            KeptEngine.release(EngineKeepReason.LiveLocation)
        }

        private fun noticeFrom(raw: Map<*, *>?): LiveLocationNotice? {
            val title = raw?.get("title") as? String ?: return null
            val text = raw["text"] as? String ?: return null
            val endsAtMs = (raw["endsAtMs"] as? Number)?.toLong() ?: return null
            return LiveLocationNotice(title, text, endsAtMs, raw["roomId"] as? String)
        }
    }
}
