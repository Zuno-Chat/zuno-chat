package im.zuno.chat.zuno_vibration

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class ZunoVibrationPlugin :
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
            "hasVibrator" -> result.success(vibrator()?.hasVibrator() == true)

            "vibrate" -> {
                val pattern = call.argument<List<Int>>("pattern")
                if (pattern == null) {
                    result.error("bad_args", "pattern is required", null)
                    return
                }
                vibrate(vibrator(), pattern, call.argument<Int>("repeat") ?: -1)
                result.success(null)
            }

            "cancel" -> {
                vibrator()?.cancel()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun vibrator(): Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val manager =
            context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
        manager?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
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
                VibrationAmplitudes.forPattern(patternLong),
                repeat,
            ),
            attributes,
        )
    }
}
