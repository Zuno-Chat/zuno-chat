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
import androidx.core.app.Person

class CallForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE)?.ifBlank { "Ongoing call" }
            ?: "Ongoing call"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        val withCamera = intent?.getBooleanExtra(EXTRA_WITH_CAMERA, false) == true

        ensureChannel()

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val hangUpIntent = PendingIntent.getBroadcast(
            this,
            HANG_UP_REQUEST_CODE,
            Intent(this, CallActionReceiver::class.java).setAction(
                CallActionReceiver.ACTION_HANG_UP,
            ),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val caller = Person.Builder().setName(title).build()
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_zuno_mark)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setContentIntent(contentIntent)
            .setStyle(NotificationCompat.CallStyle.forOngoingCall(caller, hangUpIntent))
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val type = if (withCamera) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Calls", NotificationManager.IMPORTANCE_LOW),
        )
    }

    companion object {
        private const val CHANNEL_ID = "calls_ongoing"
        private const val NOTIFICATION_ID = 4001
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_WITH_CAMERA = "withCamera"
        private const val HANG_UP_REQUEST_CODE = 4101

        fun start(context: Context, title: String, text: String, withCamera: Boolean) {
            val intent = Intent(context, CallForegroundService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_WITH_CAMERA, withCamera)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallForegroundService::class.java))
        }
    }
}
