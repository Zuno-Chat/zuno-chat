package im.zuno.chat.zuno_notifications

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONObject

class CallStyleChannel :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var assets: FlutterPlugin.FlutterAssets
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        assets = binding.flutterAssets
        channel = MethodChannel(binding.binaryMessenger, "zuno/call_style")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachTo(binding)
        silenceIfAnswered(binding.activity.intent)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachTo(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachFromActivity()
    }

    override fun onDetachedFromActivity() {
        detachFromActivity()
    }

    override fun onNewIntent(intent: Intent): Boolean {
        silenceIfAnswered(intent)
        return false
    }

    private fun attachTo(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
    }

    private fun detachFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    private fun silenceIfAnswered(intent: Intent?) {
        if (intent == null) return
        val answered = RingDecisions.answered(
            intent.action,
            intent.getIntExtra(NOTIFICATION_ID_EXTRA, -1),
            intent.getStringExtra(ACTION_ID_EXTRA),
        )
        if (!answered) return
        val callId = try {
            JSONObject(intent.getStringExtra(PAYLOAD_EXTRA) ?: "").opt("callId") as? String
        } catch (e: Exception) {
            null
        }
        IncomingRing.stopFor(context, callId, takeDownNotification = false)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "showIncomingCallStyle" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                result.success(show(context, args))
            }

            "cancelIncomingCallStyle" -> {
                val callId = (call.arguments as? Map<*, *>)?.get("callId") as? String
                result.success(IncomingRing.dismiss(context, callId))
            }

            "ringIncomingCallStyleAloud" -> {
                val callId = (call.arguments as? Map<*, *>)?.get("callId") as? String
                callId?.let { IncomingRing.ringAloud(context, it) }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun show(context: Context, args: Map<String, Any?>): Boolean {
        val spec = IncomingCallSpec.from(args) ?: return false
        return IncomingCallStyle.show(context, spec) { assets.getAssetFilePathByName(it) }
    }

    private companion object {
        const val NOTIFICATION_ID_EXTRA = RingDecisions.NOTIFICATION_ID_EXTRA
        const val PAYLOAD_EXTRA = IncomingCallStyle.PAYLOAD_EXTRA
        const val ACTION_ID_EXTRA = RingDecisions.ACTION_ID_EXTRA
    }
}
