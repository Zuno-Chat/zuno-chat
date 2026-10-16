package im.zuno.chat.zuno_notifications

import android.content.Context
import android.media.AudioAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class VibrationChannel :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "zuno/vibration")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "hasVibrator" -> result.success(Vibration.vibrator(context)?.hasVibrator() == true)

            "vibrate" -> {
                val pattern = call.argument<List<Int>>("pattern")
                if (pattern == null) {
                    result.error("bad_args", "pattern is required", null)
                    return
                }
                vibrate(Vibration.vibrator(context), pattern, call.argument<Int>("repeat") ?: -1)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(vibrator: Vibrator?, pattern: List<Int>, repeat: Int) {
        if (vibrator == null || !vibrator.hasVibrator()) return
        val patternLong = LongArray(pattern.size) { pattern[it].toLong() }
        val attributes = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()
        vibrator.vibrate(
            VibrationEffect.createWaveform(
                patternLong,
                Vibration.amplitudes(patternLong),
                repeat,
            ),
            attributes,
        )
    }
}
