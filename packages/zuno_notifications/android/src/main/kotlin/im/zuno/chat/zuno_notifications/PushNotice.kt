package im.zuno.chat.zuno_notifications

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import java.util.concurrent.atomic.AtomicInteger

object PushNotice {
    const val PREFERENCES = "FlutterSharedPreferences"
    const val ROOM_CACHE_KEY = "flutter.notifications.rooms"
    const val TONE_KEY = "flutter.settings.message_tone_enabled"
    const val VIBRATION_KEY = "flutter.settings.message_vibration_enabled"
    const val NOTIFY_ME_KEY = "flutter.settings.notify_me"
    private const val TAG = "PushNotice"
    private const val SMALL_ICON = "ic_stat_zuno_mark"
    private val vibrationPattern = longArrayOf(0, 300, 150, 300)

    val liveEngines = AtomicInteger()
    private val posted = HashMap<String, String>()

    fun post(
        context: Context,
        roomId: String?,
        eventId: String?,
        liveEngines: Int = this.liveEngines.get(),
    ) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val notificationId = roomId?.let { NotificationIds.messageNotificationIdFor(it) }
            val showing =
                notificationId != null && manager.activeNotifications.any { it.id == notificationId }
            if (!PushNoticeDecision.shouldPost(roomId, eventId, liveEngines, showing)) return
            if (roomId == null || eventId == null || notificationId == null) return
            val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            if (PushNoticeDecision.mutedByNotifyMe(prefs.getString(NOTIFY_ME_KEY, null))) {
                Log.d(TAG, "Notify me is mentions only, no instant notice")
                return
            }
            val cached = PushNoticeDecision.parseRoomCache(prefs.getString(ROOM_CACHE_KEY, null))[roomId]
            val channel = PushNoticeDecision.channelFor(cached)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                manager.getNotificationChannel(channel) == null
            ) {
                Log.d(TAG, "No $channel channel yet, no instant notice")
                return
            }
            val copy = PushNoticeDecision.copyFor(cached)
            val tap = PendingIntent.getActivity(
                context,
                notificationId,
                RoomLaunchIntent.forRoom(context, roomId),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val builder = NotificationCompat.Builder(context, channel)
                .setSmallIcon(smallIcon(context))
                .setContentTitle(copy.title)
                .setContentText(copy.text)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setSilent(!prefs.getBoolean(TONE_KEY, true))
                .setAutoCancel(true)
                .setContentIntent(tap)
                .setShortcutId(roomId)
            PushNoticeDecision.conversationFor(cached)?.let { conversation ->
                if (!ConversationShortcut.exists(context, roomId)) {
                    ConversationShortcut.push(context, roomId, conversation.title, conversation.isGroup, null)
                }
                val sender = Person.Builder().setName(conversation.title).setKey(roomId).build()
                builder.setStyle(
                    NotificationCompat.MessagingStyle(Person.Builder().setName("You").setKey("me").build())
                        .setConversationTitle(if (conversation.isGroup) conversation.title else null)
                        .setGroupConversation(conversation.isGroup)
                        .addMessage(copy.text, System.currentTimeMillis(), sender),
                )
            }
            manager.notify(notificationId, builder.build())
            synchronized(posted) { posted[roomId] = eventId }
            if (prefs.getBoolean(VIBRATION_KEY, true)) vibrate(context)
            Log.d(TAG, "Instant notice posted for $roomId")
        } catch (e: Exception) {
            Log.w(TAG, "Could not post the instant notice", e)
        }
    }

    fun take(roomId: String, eventId: String): Boolean = synchronized(posted) {
        if (posted[roomId] != eventId) return false
        posted.remove(roomId)
        true
    }

    private fun smallIcon(context: Context): Int {
        val id = context.resources.getIdentifier(SMALL_ICON, "drawable", context.packageName)
        return if (id != 0) id else context.applicationInfo.icon
    }

    private fun vibrate(context: Context) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            if (vibrator == null || !vibrator.hasVibrator()) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(vibrationPattern, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(vibrationPattern, -1)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not vibrate for the instant notice", e)
        }
    }
}
