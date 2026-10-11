package im.zuno.chat.zuno_notifications

import android.content.Context
import android.os.Build
import android.os.Vibrator
import android.os.VibratorManager

object Vibration {
    private const val FULL_STRENGTH = 255

    fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    fun amplitudes(pattern: LongArray): IntArray =
        IntArray(pattern.size) { if (it % 2 == 1) FULL_STRENGTH else 0 }
}
