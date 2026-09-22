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

// This app's own replacement for the `vibration` package's Android side,
// for the ring and message buzzes notification_sound_player.dart drives.
//
// Why not the plugin: com.benjaminabel:vibration (read directly —
// Vibration.java) hardcodes AudioAttributes.USAGE_ALARM on *every*
// vibrate() call it makes, Dart-side pattern/intensities included, with
// no parameter anywhere to ask for anything else. Found live via
// `dumpsys vibrator_manager`: a message buzz — 120ms, matching this app's
// own messageVibrationPattern exactly — showed up filed under `usage:
// ALARM`. It still physically ran (the same dump shows status
// `finished`, amplitude 1.0), so this isn't why a buzz went unfelt, but
// tagging an incoming-message vibration as an alarm is wrong regardless,
// and there's no way to fix it from the Dart side of a plugin that never
// exposes the choice.
//
// Why this is a real local *plugin* — a FlutterPlugin, `pluginClass` in
// pubspec.yaml, everything — rather than a plain class the app's own
// Activity/Service manually attach() to an engine (which is what this
// started as): there turned out to be a *third* place a FlutterEngine
// gets built that this app doesn't control the construction of at all —
// firebase_messaging's own `FlutterFirebaseMessagingBackgroundExecutor`
// builds a bare `FlutterEngine(context)` internally, with no subclass or
// override hook the way UnifiedPushService provides one. Found live:
// "message vibration failed: MissingPluginException(No implementation
// found for method hasVibrator on channel zuno/vibration)" from exactly
// that engine, while the sound half worked fine in the same run —
// because `audioplayers` (a real pub plugin) gets auto-registered by
// `FlutterEngine`'s own constructor on *every* engine anyone builds,
// which a hand-attached channel simply cannot be, no matter how many
// call sites remember to attach it. Making this a real plugin puts it on
// that same automatic path — the fix generalizes to every engine this
// app has now *and* any future one, instead of being the next call site
// someone has to remember.
class ZunoVibrationPlugin : FlutterPlugin, MethodCallHandler {
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
                vibrate(
                    vibrator(),
                    pattern,
                    call.argument<Int>("repeat") ?: -1,
                    call.argument<String>("usage"),
                )
                result.success(null)
            }
            "cancel" -> {
                vibrator()?.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun vibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager =
                context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(vibrator: Vibrator?, pattern: List<Int>, repeat: Int, usage: String?) {
        if (vibrator == null || !vibrator.hasVibrator()) return
        val patternLong = LongArray(pattern.size) { pattern[it].toLong() }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(usageFor(usage))
                .build()
            vibrator.vibrate(
                VibrationEffect.createWaveform(
                    patternLong,
                    VibrationAmplitudes.forPattern(patternLong),
                    repeat,
                ),
                attributes,
            )
        } else {
            vibrator.vibrate(patternLong, repeat)
        }
    }

    // The two callers this app has — see notification_sound_player.dart's
    // ringAudioContext/messageAudioContext for the exact same split on the
    // audio side, which this mirrors on purpose rather than inventing a
    // third categorization scheme.
    private fun usageFor(usage: String?): Int = when (usage) {
        "ringtone" -> AudioAttributes.USAGE_NOTIFICATION_RINGTONE
        else -> AudioAttributes.USAGE_NOTIFICATION
    }
}
