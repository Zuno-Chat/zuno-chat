package im.zuno.chat

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class FcmChannel(context: Context, private val engineId: Int, activity: Activity?) :
    MethodChannel.MethodCallHandler {
    private val context = context.applicationContext
    private val activity = activity?.let { WeakReference(it) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> result.success(FcmRouter.ready(engineId))

            "availability" -> result.success(FcmPlatform.availability(context).wire)

            "getToken" -> FcmPlatform.token(context) { outcome ->
                when (outcome) {
                    is FcmTokenOutcome.Token -> result.success(outcome.token)

                    is FcmTokenOutcome.Failure -> result.error(
                        outcome.failure.wire,
                        outcome.message,
                        null,
                    )
                }
            }

            "deleteToken" -> FcmPlatform.deleteToken(context) { error ->
                if (error == null) {
                    result.success(null)
                } else {
                    result.error(FcmTokenFailure.FAILED.wire, error.message, null)
                }
            }

            "fixPlayServices" -> {
                val host = activity?.get()
                if (host == null || host.isFinishing || host.isDestroyed) {
                    result.success(FcmPlatform.availability(context).wire)
                } else {
                    FcmPlatform.fixPlayServices(host) { result.success(it.wire) }
                }
            }

            else -> result.notImplemented()
        }
    }
}
