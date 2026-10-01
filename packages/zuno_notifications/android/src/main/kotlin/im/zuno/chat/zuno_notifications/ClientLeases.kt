package im.zuno.chat.zuno_notifications

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object ClientLeases {
    const val CHANNEL = "zuno/client_lease"
    private const val TAG = "ClientLeases"

    private val main = Handler(Looper.getMainLooper())
    private val book = ClientLeaseBook()
    private val channels = HashMap<Long, MethodChannel>()
    private val pending = HashMap<Long, MethodChannel.Result>()
    private var lastEngine = 0L
    private var lastRequest = 0L

    fun attach(messenger: BinaryMessenger): Long {
        val engine = ++lastEngine
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler { call, result -> handle(engine, call, result) }
        channels[engine] = channel
        return engine
    }

    fun detach(engine: Long) {
        channels.remove(engine)?.setMethodCallHandler(null)
        perform(book.detached(engine))
    }

    private fun handle(engine: Long, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> acquire(engine, call, result)

            "release" -> {
                call.argument<String>("token")?.let { perform(book.release(it)) }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun acquire(engine: Long, call: MethodCall, result: MethodChannel.Result) {
        val kind = ClientLeaseKind.fromWire(call.argument<String>("kind"))
        if (kind == null) {
            result.error("bad_args", "kind must be app or background", null)
            return
        }
        val waitMs = call.argument<Number>("waitMs")?.toLong()?.coerceAtLeast(0) ?: 0
        val request = ++lastRequest
        pending[request] = result
        perform(book.acquire(request, engine, kind))
        if (book.isWaiting(request)) {
            main.postDelayed({ perform(book.timedOut(request)) }, waitMs)
        }
    }

    private fun reply(request: Long, token: String?) {
        val result = pending.remove(request) ?: return
        try {
            result.success(token)
        } catch (e: Exception) {
            Log.w(TAG, "Could not answer lease request $request", e)
        }
    }

    private fun perform(actions: List<ClientLeaseAction>) {
        for (action in actions) {
            when (action) {
                is ClientLeaseAction.Grant -> {
                    if (action.forced) {
                        Log.w(TAG, "The app took the Matrix client while another engine held it")
                    }
                    reply(action.request, action.token)
                }

                is ClientLeaseAction.Deny -> reply(action.request, null)

                is ClientLeaseAction.Yield -> try {
                    channels[action.engine]?.invokeMethod("yield", null)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not ask engine ${action.engine} to let its client go", e)
                }
            }
        }
    }
}
