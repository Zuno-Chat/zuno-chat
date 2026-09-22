package im.zuno.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class UploadForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel(this)
        val notification = buildNotification(this, progress)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = true
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
        stopForeground(STOP_FOREGROUND_REMOVE)
        NotificationManagerCompat.from(this).cancel(NOTIFICATION_ID)
    }

    private data class Progress(val label: String, val percent: Int?)

    companion object {
        private const val CHANNEL_ID = "uploads"
        private const val NOTIFICATION_ID = 4004
        private const val DEFAULT_LABEL = "Uploading…"

        @Volatile private var running = false
        @Volatile private var progress = Progress(DEFAULT_LABEL, null)

        fun start(context: Context): Boolean {
            progress = Progress(DEFAULT_LABEL, null)
            return try {
                context.startForegroundService(Intent(context, UploadForegroundService::class.java))
                true
            } catch (error: IllegalStateException) {
                false
            } catch (error: SecurityException) {
                false
            }
        }

        fun update(context: Context, label: String, percent: Int?) {
            progress = Progress(label, percent)
            if (!running) return
            try {
                NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, buildNotification(context, progress))
            } catch (error: SecurityException) {
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, UploadForegroundService::class.java))
        }

        private fun buildNotification(context: Context, progress: Progress): Notification {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentIntent = launchIntent?.let {
                PendingIntent.getActivity(
                    context,
                    0,
                    it,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            }
            val percent = progress.percent
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(progress.label)
                .setSmallIcon(R.drawable.ic_stat_zuno_mark)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setProgress(100, percent ?: 0, percent == null)
                .setContentIntent(contentIntent)
                .build()
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Uploads", NotificationManager.IMPORTANCE_LOW),
            )
        }
    }
}
