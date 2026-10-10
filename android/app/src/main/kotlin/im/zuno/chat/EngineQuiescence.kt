package im.zuno.chat

import android.content.Context
import android.os.Handler
import io.flutter.plugin.common.MethodChannel

object EngineQuiescence {
    private const val METHOD = "quiescent"
    const val ANSWER_TIMEOUT_MS = 5_000L

    fun ask(context: Context, channel: MethodChannel, main: Handler, done: (Boolean) -> Unit) {
        var answered = false
        fun finish(quiet: Boolean) {
            if (answered) return
            answered = true
            done(quiet)
        }
        val timeout = Runnable { finish(false) }
        fun answer(quiet: Boolean) {
            main.removeCallbacks(timeout)
            finish(quiet)
        }
        main.postDelayed(timeout, ANSWER_TIMEOUT_MS)
        try {
            channel.invokeMethod(
                METHOD,
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        answer(result == true)
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        answer(false)
                    }

                    override fun notImplemented() {
                        answer(false)
                    }
                },
            )
        } catch (e: Exception) {
            CaughtErrors.record(context, "engine quiescence ask", e)
            answer(false)
        }
    }
}
