package im.zuno.chat.zuno_call_style

import android.app.AlarmManager
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import org.json.JSONObject

object IncomingRing {
    const val NOTIFICATION_ID = 4002
    const val ACTION_TIMED_OUT = "im.zuno.chat.zuno_call_style.RING_TIMED_OUT"
    const val ACTION_DISMISSED = "im.zuno.chat.zuno_call_style.RING_DISMISSED"
    const val EXTRA_CALL_ID = "callId"
    private const val TAG = "IncomingRing"
    private const val PREFERENCES = "FlutterSharedPreferences"
    private const val REMEMBERED_RING_KEY = "flutter.calls.ringing_notification"
    private const val BACKSTOP_WINDOW_MS = 5_000L
    private const val TIMEOUT_REQUEST_CODE = NOTIFICATION_ID * 16 + 2
    private const val DISMISS_REQUEST_CODE = NOTIFICATION_ID * 16 + 3
    private const val TONE_COPY = "zuno_ringtone"

    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private var ringingCallId: String? = null
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var timeout: Runnable? = null

    @Synchronized
    fun present(
        context: Context,
        callId: String,
        notification: Notification,
        toneKey: String?,
        vibrationPattern: LongArray?,
    ) {
        val app = context.applicationContext
        silence(app)
        NotificationManagerCompat.from(app).notify(NOTIFICATION_ID, notification)
        ringingCallId = callId
        player = toneKey?.let { startTone(app, it) }
        vibrator = vibrationPattern?.let { startVibration(app, it) }
        armTimeout(app, callId)
    }

    @Synchronized
    fun dismiss(context: Context, callId: String?): Boolean {
        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val decision = RingDecisions.cancel(
            callId,
            ringingCallId,
            remembered(runCatching { prefs.getString(REMEMBERED_RING_KEY, null) }.getOrNull()),
            System.currentTimeMillis(),
        )
        if (decision.forget) prefs.edit().remove(REMEMBERED_RING_KEY).apply()
        if (decision.dismiss) {
            NotificationManagerCompat.from(app).cancel(NOTIFICATION_ID)
            silence(app)
        }
        return decision.dismiss
    }

    @Synchronized
    fun stopFor(context: Context, callId: String?, takeDownNotification: Boolean) {
        if (!RingDecisions.stops(ringingCallId, callId)) return
        val app = context.applicationContext
        if (takeDownNotification) NotificationManagerCompat.from(app).cancel(NOTIFICATION_ID)
        silence(app)
    }

    fun dismissIntent(context: Context, callId: String): PendingIntent = PendingIntent.getBroadcast(
        context,
        DISMISS_REQUEST_CODE,
        stopIntent(context, ACTION_DISMISSED, callId),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    @Synchronized
    private fun startIfCurrent(prepared: MediaPlayer) {
        if (player === prepared) prepared.start()
    }

    @Synchronized
    private fun dropIfCurrent(failed: MediaPlayer, what: Int, extra: Int) {
        Log.w(TAG, "Ringtone failed ($what, $extra)")
        if (player === failed) player = null
        failed.release()
    }

    private fun silence(app: Context) {
        ringingCallId = null
        player?.release()
        player = null
        try {
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "Could not stop the ring vibration", e)
        }
        vibrator = null
        timeout?.let { mainHandler.removeCallbacks(it) }
        timeout = null
        cancelTimeoutAlarm(app)
    }

    private fun remembered(stored: String?): RememberedRing? {
        if (stored == null) return null
        return try {
            val record = JSONObject(stored)
            RememberedRing.of(record.opt("roomId"), record.opt("callId"), record.opt("postedAt"))
        } catch (e: Exception) {
            null
        }
    }

    private fun startTone(app: Context, toneKey: String): MediaPlayer? {
        val tone = MediaPlayer()
        return try {
            tone.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            setToneSource(app, tone, toneKey)
            tone.isLooping = true
            tone.setOnPreparedListener { startIfCurrent(it) }
            tone.setOnErrorListener { failed, what, extra ->
                dropIfCurrent(failed, what, extra)
                true
            }
            tone.prepareAsync()
            tone
        } catch (e: Exception) {
            Log.w(TAG, "Could not play the ringtone", e)
            tone.release()
            null
        }
    }

    private fun setToneSource(app: Context, tone: MediaPlayer, toneKey: String) {
        try {
            app.assets.openFd(toneKey).use {
                tone.setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
        } catch (e: FileNotFoundException) {
            FileInputStream(copiedTone(app, toneKey)).use { tone.setDataSource(it.fd) }
        }
    }

    private fun copiedTone(app: Context, toneKey: String): File {
        val bytes = app.assets.open(toneKey).use { it.readBytes() }
        val copy = File(app.cacheDir, TONE_COPY)
        if (copy.isFile && copy.readBytes().contentEquals(bytes)) return copy
        val partial = File(app.cacheDir, "$TONE_COPY.partial")
        partial.writeBytes(bytes)
        if (!partial.renameTo(copy)) throw FileNotFoundException("Could not keep $toneKey")
        return copy
    }

    @Suppress("DEPRECATION")
    private fun startVibration(app: Context, pattern: LongArray): Vibrator? = try {
        systemVibrator(app)?.takeIf { it.hasVibrator() }?.also {
            it.vibrate(
                VibrationEffect.createWaveform(pattern, RingDecisions.amplitudes(pattern), 0),
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .build(),
            )
        }
    } catch (e: Exception) {
        Log.w(TAG, "Could not vibrate for the ring", e)
        null
    }

    private fun systemVibrator(app: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            app.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    private fun armTimeout(app: Context, callId: String) {
        val stop = Runnable { stopFor(app, callId, takeDownNotification = true) }
        timeout = stop
        mainHandler.postDelayed(stop, RingDecisions.RING_TIMEOUT_MS)
        try {
            app.getSystemService(AlarmManager::class.java)?.setWindow(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + RingDecisions.RING_TIMEOUT_MS,
                BACKSTOP_WINDOW_MS,
                PendingIntent.getBroadcast(
                    app,
                    TIMEOUT_REQUEST_CODE,
                    stopIntent(app, ACTION_TIMED_OUT, callId),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not arm the ring timeout", e)
        }
    }

    private fun cancelTimeoutAlarm(app: Context) {
        try {
            val armed = PendingIntent.getBroadcast(
                app,
                TIMEOUT_REQUEST_CODE,
                stopIntent(app, ACTION_TIMED_OUT, null),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            ) ?: return
            app.getSystemService(AlarmManager::class.java)?.cancel(armed)
            armed.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "Could not cancel the ring timeout", e)
        }
    }

    private fun stopIntent(context: Context, action: String, callId: String?): Intent =
        Intent(context, RingStopReceiver::class.java)
            .setAction(action)
            .putExtra(EXTRA_CALL_ID, callId)
}
