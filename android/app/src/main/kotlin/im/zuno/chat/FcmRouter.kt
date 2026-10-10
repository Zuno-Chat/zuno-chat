package im.zuno.chat

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicLong

object FcmRouter {
    const val CHANNEL = "zuno/fcm"
    const val HEADLESS_ARG = "--fcm-bg"
    private const val TAG = "FcmRouter"
    private const val MAX_RETIRE_ATTEMPTS = 20
    private const val RETIRE_RETRY_MS = 30_000L

    private class Job(
        val id: String,
        val method: String,
        val args: Map<String, Any?>,
        val done: CountDownLatch,
    )

    private class EngineHandle(
        val channel: MethodChannel,
        val headless: FlutterEngine?,
        val context: Context,
    )

    private val main = Handler(Looper.getMainLooper())
    private val routing = FcmRouting()
    private val jobs = HashMap<String, Job>()
    private val engines = HashMap<Int, EngineHandle>()
    private val sequence = AtomicLong()
    private var appContext: Context? = null
    private var tick: Runnable? = null

    fun deliver(
        context: Context,
        method: String,
        args: Map<String, Any?>,
        key: String,
    ): CountDownLatch {
        val id = "$key#${sequence.incrementAndGet()}"
        val job = Job(id, method, args + ("id" to id), CountDownLatch(1))
        val app = context.applicationContext
        main.post {
            appContext = app
            jobs[id] = job
            perform(routing.submit(id, now()))
        }
        return job.done
    }

    fun attachApp(engine: FlutterEngine, activity: Activity): Int {
        appContext = activity.applicationContext
        val attached = routing.appAttached(now())
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(FcmChannel(activity, attached.engineId, activity))
        engines[attached.engineId] = EngineHandle(channel, null, activity.applicationContext)
        perform(attached.actions)
        return attached.engineId
    }

    fun detachApp(engineId: Int) {
        engines.remove(engineId)?.channel?.setMethodCallHandler(null)
        perform(routing.gone(engineId, now()))
    }

    fun rebindApp(engineId: Int, activity: Activity) {
        engines[engineId]?.channel?.setMethodCallHandler(FcmChannel(activity, engineId, activity))
    }

    fun ready(engineId: Int): Boolean {
        if (engineId !in engines) return false
        perform(routing.ready(engineId, now()))
        val accepted = routing.isReady(engineId)
        Log.d(TAG, "Engine $engineId ${if (accepted) "takes pushes" else "is not needed"}")
        return accepted
    }

    private fun perform(actions: List<FcmRouteAction>) {
        for (action in actions) {
            when (action) {
                is FcmRouteAction.Send -> send(action)
                is FcmRouteAction.BootHeadless -> boot(action.engineId)
                is FcmRouteAction.RetireHeadless -> retire(action.engineId)
                is FcmRouteAction.DestroyHeadless -> destroy(action.engineId)
                is FcmRouteAction.Finish -> jobs.remove(action.jobId)?.done?.countDown()
            }
        }
        scheduleTick()
    }

    private fun send(action: FcmRouteAction.Send) {
        if (!routing.isInFlight(action.jobId, action.engineId)) return
        val job = jobs[action.jobId] ?: return perform(routing.handled(action.jobId, now()))
        val handle = engines[action.engineId] ?: return perform(routing.sendFailed(job.id, now()))
        try {
            handle.channel.invokeMethod(
                job.method,
                job.args,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        perform(routing.handled(job.id, now()))
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        Log.w(TAG, "Dart could not handle ${job.method} ($code: $message)")
                        perform(routing.handled(job.id, now()))
                    }

                    override fun notImplemented() {
                        Log.w(TAG, "Engine ${action.engineId} has no ${job.method} handler")
                        perform(routing.sendFailed(job.id, now()))
                    }
                },
            )
        } catch (e: Exception) {
            CaughtErrors.record(handle.context, "fcm deliver ${job.method}", e)
            perform(routing.sendFailed(job.id, now()))
        }
    }

    private fun boot(engineId: Int) {
        val context = appContext ?: return perform(routing.bootFailed(engineId, now()))
        Log.d(TAG, "Starting push engine $engineId")
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) loader.startInitialization(context)
            loader.ensureInitializationCompleteAsync(context, null, main) {
                if (routing.isStarting(engineId)) start(context, engineId)
            }
        } catch (e: Exception) {
            CaughtErrors.record(context, "fcm push engine prepare", e)
            perform(routing.bootFailed(engineId, now()))
        }
    }

    private fun start(context: Context, engineId: Int) {
        try {
            val engine = PushEnginePlugins.create(context)
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(FcmChannel(context, engineId, null))
            engines[engineId] = EngineHandle(channel, engine, context)
            engine.localizationPlugin.sendLocalesToFlutter(context.resources.configuration)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
                listOf(HEADLESS_ARG),
            )
        } catch (e: Exception) {
            CaughtErrors.record(context, "fcm push engine start", e)
            destroy(engineId)
            perform(routing.bootFailed(engineId, now()))
        }
    }

    private fun retire(engineId: Int, attempt: Int = 0) {
        val handle = engines[engineId] ?: return perform(routing.gone(engineId, now()))
        EngineQuiescence.ask(handle.context, handle.channel, main) { quiet ->
            if (engines[engineId] !== handle) return@ask
            when {
                quiet -> perform(routing.quiet(engineId, now()))

                !routing.isBroken(engineId) -> perform(routing.busy(engineId, now()))

                attempt + 1 < MAX_RETIRE_ATTEMPTS -> main.postDelayed(
                    { retire(engineId, attempt + 1) },
                    RETIRE_RETRY_MS,
                )

                else -> Log.w(TAG, "Push engine $engineId never went quiet; leaving it running")
            }
        }
    }

    private fun destroy(engineId: Int) {
        val handle = engines.remove(engineId) ?: return
        handle.channel.setMethodCallHandler(null)
        try {
            handle.headless?.destroy()
            Log.d(TAG, "Push engine $engineId destroyed")
        } catch (e: Exception) {
            CaughtErrors.record(handle.context, "fcm push engine destroy", e)
        }
    }

    private fun scheduleTick() {
        tick?.let { main.removeCallbacks(it) }
        tick = null
        val at = routing.nextTickAt(now()) ?: return
        val runnable = Runnable {
            tick = null
            perform(routing.tick(now()))
        }
        tick = runnable
        main.postDelayed(runnable, (at - now()).coerceAtLeast(0))
    }

    private fun now(): Long = SystemClock.elapsedRealtime()
}
