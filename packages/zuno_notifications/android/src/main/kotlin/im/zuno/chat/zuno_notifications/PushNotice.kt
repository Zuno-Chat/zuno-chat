package im.zuno.chat.zuno_notifications

import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person

object PushNotice {
    const val PREFERENCES = "FlutterSharedPreferences"
    const val ROOM_CACHE_KEY = "flutter.notifications.rooms"
    const val TONE_KEY = "flutter.settings.message_tone_enabled"
    const val VIBRATION_KEY = "flutter.settings.message_vibration_enabled"
    const val NOTIFY_ME_KEY = "flutter.settings.notify_me"
    private const val TAG = "PushNotice"
    private const val SMALL_ICON = "ic_stat_zuno_mark"
    private val vibrationPattern = longArrayOf(0, 300, 150, 300)
    private const val MISSED_CHANNEL = "direct_messages"
    private const val MISSED_NOTIFICATION_ID = 4105
    private const val MISSED_TITLE = "Zuno"
    private const val MISSED_TEXT =
        "Some notifications could not be delivered. Open Zuno to see new messages."

    private const val TEST_TITLE = "Zuno"
    private const val TEST_TEXT = "Notifications work"

    private val posted = HashMap<String, String>()

    fun appInFront(context: Context): Boolean {
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard?.isKeyguardLocked == true) return false
        val state = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(state)
        return state.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    }

    fun post(
        context: Context,
        roomId: String?,
        eventId: String?,
        appInFront: Boolean = appInFront(context),
    ): Boolean {
        var notified = false
        try {
            val manager = context.getSystemService(
                Context.NOTIFICATION_SERVICE,
            ) as NotificationManager
            val notificationId = roomId?.let { NotificationIds.messageNotificationIdFor(it) }
            val showing =
                notificationId != null &&
                    manager.activeNotifications.any { it.id == notificationId }
            if (!PushNoticeDecision.shouldPost(roomId, eventId, appInFront, showing)) return false
            if (roomId == null || eventId == null || notificationId == null) return false
            val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            if (PushNoticeDecision.mutedByNotifyMe(prefs.getString(NOTIFY_ME_KEY, null))) {
                Log.d(TAG, "Notify me is mentions only, no instant notice")
                return false
            }
            val cached = PushNoticeDecision.parseRoomCache(
                prefs.getString(ROOM_CACHE_KEY, null),
            )[roomId]
            val channel = PushNoticeDecision.channelFor(cached)
            if (manager.getNotificationChannel(channel) == null) {
                Log.d(TAG, "No $channel channel yet, no instant notice")
                return false
            }
            val copy = PushNoticeDecision.copyFor(cached)
            val alert = alertFor(prefs)
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
                .setSilent(alert.silent)
                .setAutoCancel(true)
                .setContentIntent(tap)
                .setShortcutId(roomId)
            PushNoticeDecision.conversationFor(cached)?.let { conversation ->
                if (!ConversationShortcut.exists(context, roomId)) {
                    ConversationShortcut.push(
                        context,
                        roomId,
                        conversation.title,
                        conversation.isGroup,
                        null,
                    )
                }
                val sender = Person.Builder().setName(conversation.title).setKey(roomId).build()
                builder.setStyle(
                    NotificationCompat.MessagingStyle(
                        Person.Builder().setName("You").setKey("me").build(),
                    )
                        .setConversationTitle(
                            if (conversation.isGroup) conversation.title else null,
                        )
                        .setGroupConversation(conversation.isGroup)
                        .addMessage(copy.text, System.currentTimeMillis(), sender),
                )
            }
            manager.notify(notificationId, builder.build())
            notified = true
            synchronized(posted) { posted[roomId] = eventId }
            if (alert.vibrate) vibrate(context)
            Log.d(TAG, "Instant notice posted for $roomId")
        } catch (e: Exception) {
            Log.w(TAG, "Could not post the instant notice", e)
        }
        return notified
    }

    fun postMissed(context: Context) {
        try {
            val manager = context.getSystemService(
                Context.NOTIFICATION_SERVICE,
            ) as NotificationManager
            val channelExists = manager.getNotificationChannel(MISSED_CHANNEL) != null
            val enabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
            if (!PushNoticeDecision.shouldPostMissed(enabled, channelExists)) return
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val tap = launch?.let {
                PendingIntent.getActivity(
                    context,
                    MISSED_NOTIFICATION_ID,
                    it,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            }
            val notification = NotificationCompat.Builder(context, MISSED_CHANNEL)
                .setSmallIcon(smallIcon(context))
                .setContentTitle(MISSED_TITLE)
                .setContentText(MISSED_TEXT)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(tap)
                .build()
            manager.notify(MISSED_NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.w(TAG, "Could not post the missed-notifications notice", e)
        }
    }

    fun postTest(context: Context): Boolean {
        try {
            val manager = context.getSystemService(
                Context.NOTIFICATION_SERVICE,
            ) as NotificationManager
            val channelExists =
                manager.getNotificationChannel(PushNoticeDecision.DIRECT_CHANNEL) != null
            val enabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
            if (!PushNoticeDecision.shouldPostMissed(enabled, channelExists)) return false
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val tap = launch?.let {
                PendingIntent.getActivity(
                    context,
                    NotificationIds.TEST_NOTIFICATION_ID,
                    it,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            }
            val alert = alertFor(context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE))
            val notification = NotificationCompat.Builder(
                context,
                PushNoticeDecision.DIRECT_CHANNEL,
            )
                .setSmallIcon(smallIcon(context))
                .setContentTitle(TEST_TITLE)
                .setContentText(TEST_TEXT)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setSilent(alert.silent)
                .setAutoCancel(true)
                .setContentIntent(tap)
                .build()
            manager.notify(NotificationIds.TEST_NOTIFICATION_ID, notification)
            if (alert.vibrate) vibrate(context)
            return true
        } catch (e: Exception) {
            Log.w(TAG, "Could not post the test notice", e)
            return false
        }
    }

    fun take(roomId: String, eventId: String): Boolean = synchronized(posted) {
        if (posted[roomId] != eventId) return false
        posted.remove(roomId)
        true
    }

    private fun alertFor(prefs: SharedPreferences): NoticeAlert = PushNoticeDecision.alertFor(
        messageTone = prefs.getBoolean(TONE_KEY, true),
        messageVibration = prefs.getBoolean(VIBRATION_KEY, true),
    )

    private fun smallIcon(context: Context): Int {
        val id = context.resources.getIdentifier(SMALL_ICON, "drawable", context.packageName)
        return if (id != 0) id else context.applicationInfo.icon
    }

    private fun vibrate(context: Context) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (
                    context.getSystemService(
                        Context.VIBRATOR_MANAGER_SERVICE,
                    ) as? VibratorManager
                    )?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            if (vibrator == null || !vibrator.hasVibrator()) return
            val effect = VibrationEffect.createWaveform(vibrationPattern, -1)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                vibrator.vibrate(
                    effect,
                    VibrationAttributes.createForUsage(VibrationAttributes.USAGE_NOTIFICATION),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(
                    effect,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not vibrate for the instant notice", e)
        }
    }
}
