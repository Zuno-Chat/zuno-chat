package im.zuno.chat.zuno_notifications

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat
import java.util.UUID
import org.json.JSONObject

class IncomingCallSpec(
    val channelId: String,
    val name: String?,
    val text: String?,
    val callerId: String,
    val isVideo: Boolean,
    val roomId: String,
    val callId: String,
    val avatarBytes: ByteArray?,
    val plan: RingPlan,
    val ringMs: Long,
) {
    companion object {
        fun from(args: Map<String, Any?>): IncomingCallSpec? = IncomingCallSpec(
            channelId = args["channelId"] as? String ?: return null,
            name = args["name"] as? String,
            text = args["text"] as? String,
            callerId = args["callerId"] as? String ?: "",
            isVideo = args["isVideo"] == true,
            roomId = args["roomId"] as? String ?: return null,
            callId = args["callId"] as? String ?: return null,
            avatarBytes = args["avatarBytes"] as? ByteArray,
            plan = RingPlan.from(args),
            ringMs = ringMsFrom(args["ringMs"]),
        )

        private fun ringMsFrom(value: Any?): Long =
            (value as? Number)?.toDouble()?.takeUnless { it.isNaN() }?.toLong()
                ?.coerceIn(1, RingDecisions.RING_TIMEOUT_MS)
                ?: RingDecisions.RING_TIMEOUT_MS
    }
}

object IncomingCallStyle {
    const val PAYLOAD_EXTRA = "payload"
    private const val RING_NOTIFICATION_ID = IncomingRing.NOTIFICATION_ID
    private const val NOTIFICATION_ID_EXTRA = RingDecisions.NOTIFICATION_ID_EXTRA
    private const val ACTION_ID_EXTRA = RingDecisions.ACTION_ID_EXTRA
    private const val CANCEL_NOTIFICATION_EXTRA = "cancelNotification"
    private const val SMALL_ICON_NAME = "ic_stat_zuno_mark"

    fun canRing(context: Context, channelId: String): Boolean {
        val manager = NotificationManagerCompat.from(context)
        val channel = manager.getNotificationChannelCompat(channelId)
        val groupBlocked = channel?.group?.let {
            manager.getNotificationChannelGroupCompat(it)?.isBlocked
        } == true
        return RingDecisions.canRing(
            manager.areNotificationsEnabled(),
            channel?.importance,
            groupBlocked,
        )
    }

    fun show(context: Context, spec: IncomingCallSpec, tonePath: (String) -> String?): Boolean {
        if (!canRing(context, spec.channelId)) return false
        val name = spec.name?.takeUnless { it.isBlank() }
            ?: context.getString(R.string.callsIncomingCall)
        val callId = spec.callId

        val payload = JSONObject().apply {
            put("roomId", spec.roomId)
            put("callId", callId)
            put("callerId", spec.callerId)
            put("isVideo", spec.isVideo)
        }.toString()

        val personBuilder = Person.Builder().setName(name)
        val avatarBytes = spec.avatarBytes
        if (avatarBytes != null) {
            val bitmap = BitmapFactory.decodeByteArray(avatarBytes, 0, avatarBytes.size)
            if (bitmap != null) {
                personBuilder.setIcon(IconCompat.createWithBitmap(bitmap))
            }
        }
        val person = personBuilder.build()

        val token = UUID.randomUUID().toString()

        val launchIntent = AppLaunchIntent.of(context, RingDecisions.SELECT_FOREGROUND_ACTION)
            .putExtra(NOTIFICATION_ID_EXTRA, RING_NOTIFICATION_ID)
            .putExtra(PAYLOAD_EXTRA, payload)
            .putExtra(RingDecisions.TOKEN_EXTRA, token)
        val contentPendingIntent = PendingIntent.getActivity(
            context,
            RING_NOTIFICATION_ID,
            launchIntent,
            pendingIntentFlags(),
        )

        val declineIntent = Intent(context, RingStopReceiver::class.java)
            .setAction(IncomingRing.ACTION_DECLINED)
            .putExtra(IncomingRing.EXTRA_CALL_ID, callId)
            .putExtra(NOTIFICATION_ID_EXTRA, RING_NOTIFICATION_ID)
            .putExtra(ACTION_ID_EXTRA, RingDecisions.DECLINE_ACTION_ID)
            .putExtra(CANCEL_NOTIFICATION_EXTRA, true)
            .putExtra(PAYLOAD_EXTRA, payload)
            .putExtra(RingDecisions.TOKEN_EXTRA, token)
        val declinePendingIntent = PendingIntent.getBroadcast(
            context,
            RING_NOTIFICATION_ID * 16,
            declineIntent,
            pendingIntentFlags(),
        )

        val answerIntent = AppLaunchIntent.of(context, RingDecisions.SELECT_FOREGROUND_ACTION)
            .putExtra(NOTIFICATION_ID_EXTRA, RING_NOTIFICATION_ID)
            .putExtra(ACTION_ID_EXTRA, RingDecisions.ANSWER_ACTION_ID)
            .putExtra(CANCEL_NOTIFICATION_EXTRA, true)
            .putExtra(PAYLOAD_EXTRA, payload)
            .putExtra(RingDecisions.TOKEN_EXTRA, token)
        val answerPendingIntent = PendingIntent.getActivity(
            context,
            RING_NOTIFICATION_ID * 16 + 1,
            answerIntent,
            pendingIntentFlags(),
        )

        val smallIcon = smallIconResId(context)
        val dismissIntent = IncomingRing.dismissIntent(context, callId)
        fun notification(line: String?, alertOnce: Boolean): Notification =
            NotificationCompat.Builder(context, spec.channelId)
                .setContentTitle(name)
                .setContentText(line)
                .setSmallIcon(smallIcon)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(alertOnce)
                .setTimeoutAfter(spec.ringMs)
                .setContentIntent(contentPendingIntent)
                .setFullScreenIntent(contentPendingIntent, true)
                .setDeleteIntent(dismissIntent)
                .setStyle(
                    NotificationCompat.CallStyle.forIncomingCall(
                        person,
                        declinePendingIntent,
                        answerPendingIntent,
                    ).setIsVideo(spec.isVideo),
                )
                .build()

        val importance = NotificationManagerCompat.from(context)
            .getNotificationChannelCompat(spec.channelId)
            ?.importance
        val ring = if (RingDecisions.ringsAloud(importance)) spec.plan else spec.plan.quiet()
        IncomingRing.present(
            context,
            callId,
            token,
            notification(ring.waitingText ?: spec.text, alertOnce = false),
            ring.toneNow?.let(tonePath),
            ring.vibrationPattern,
            spec.ringMs,
            if (ring.waiting) {
                AloudRing(
                    notification(spec.text, alertOnce = true),
                    ring.ringtoneAsset?.let(tonePath),
                )
            } else {
                null
            },
        )
        return true
    }

    private fun smallIconResId(context: Context): Int = context.resources.getIdentifier(
        SMALL_ICON_NAME,
        "drawable",
        context.packageName,
    )

    private fun pendingIntentFlags(): Int =
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
}
