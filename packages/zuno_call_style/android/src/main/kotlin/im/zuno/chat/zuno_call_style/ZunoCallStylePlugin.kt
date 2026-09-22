package im.zuno.chat.zuno_call_style

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONObject

// Builds and posts the incoming-call ring notification using Android's
// NotificationCompat.CallStyle — unavailable through
// flutter_local_notifications (this app's pinned 22.3.0 has no CallStyle
// API), so this posts directly via NotificationManagerCompat instead of
// going through the plugin's own Notification.Builder.
//
// The channel (already registered by CallNotificationService.initialize())
// and notification id (4002, matching _ringNotificationId in
// call_notification_service.dart) are unchanged — only how the
// Notification object for that id gets built.
//
// Why this is a real local *plugin* — a FlutterPlugin, `pluginClass` in
// pubspec.yaml, its own package under packages/ — rather than an object
// the app's own Activity hand-attaches to a MethodChannel in
// configureFlutterEngine (which is what this started as): a
// hand-attached channel exists only on the engine that attached it, and
// the ring's most important case is the one where that engine doesn't
// exist. A push-delivered ring arrives with the app process killed and
// runs on a *headless* engine — either ZunoPushService's (UnifiedPush)
// or, worse, firebase_messaging's own
// `FlutterFirebaseMessagingBackgroundExecutor`, which builds a bare
// `FlutterEngine(context)` internally with no subclass or override hook
// this app can reach at all. On those engines the manual channel has no
// handler, `_invoke` swallows the MissingPluginException, and the phone
// silently never rings. `packages/zuno_vibration` exists for exactly
// this reason, found live on the sound/vibration path — see
// ZunoVibrationPlugin's doc comment. A real plugin is auto-registered by
// GeneratedPluginRegistrant on every engine anyone builds, including the
// ones this app never constructs, so the guarantee holds by
// construction rather than by every call site remembering to attach.
//
// The channel name is `zuno/call_style`, deliberately not the app's
// existing `zuno/calls`: MethodChannel.setMethodCallHandler replaces any
// previous handler for a name outright, so sharing one would make this
// plugin and MainActivity's own manual handler race to clobber each
// other on the Activity's engine.
//
// Accept and Decline PendingIntents are built to exactly match the
// Intent shape flutter_local_notifications' own action-building code
// produces (FlutterLocalNotificationsPlugin.java, verified against the
// pinned 22.3.0 source) so its existing dispatch keeps working
// unmodified:
//  - Accept mirrors a `showsUserInterface: true` action: PendingIntent
//    .getActivity into this app's own launch intent, action
//    "SELECT_FOREGROUND_NOTIFICATION" — the plugin's own activity-aware
//    listener picks this up exactly as it does for a plugin-built action.
//  - Decline mirrors a `showsUserInterface: false` action: PendingIntent
//    .getBroadcast targeting the plugin's own ActionBroadcastReceiver
//    (already declared in AndroidManifest.xml) with action
//    "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver
//    .ACTION_TAPPED" — that receiver boots the headless engine and
//    dispatches to onDidReceiveBackgroundNotificationResponse
//    (_handleBackgroundCallResponse in call_notification_service.dart),
//    unchanged.
// This is an undocumented contract of the plugin, not a public API — a
// flutter_local_notifications major-version bump needs re-verifying it
// still holds.
class ZunoCallStylePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "zuno/call_style")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "showIncomingCallStyle" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                show(context, args)
                result.success(null)
            }
            "cancelIncomingCallStyle" -> {
                cancel(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun show(context: Context, args: Map<String, Any?>) {
        val channelId = args["channelId"] as? String ?: return
        val title = args["title"] as? String ?: ""
        // CallStyle throws IllegalArgumentException on a Person with a
        // blank name, so this fallback is load-bearing, not cosmetic.
        val callerName =
            (args["callerName"] as? String)?.ifBlank { FALLBACK_CALLER_NAME }
                ?: FALLBACK_CALLER_NAME
        val callerId = args["callerId"] as? String ?: ""
        val isVideo = args["isVideo"] == true
        val roomId = args["roomId"] as? String ?: return
        val callId = args["callId"] as? String ?: return
        val avatarBytes = args["avatarBytes"] as? ByteArray

        val payload = JSONObject().apply {
            put("roomId", roomId)
            put("callId", callId)
            put("callerId", callerId)
            put("isVideo", isVideo)
        }.toString()

        val personBuilder = Person.Builder().setName(callerName)
        if (avatarBytes != null) {
            val bitmap = BitmapFactory.decodeByteArray(avatarBytes, 0, avatarBytes.size)
            if (bitmap != null) {
                personBuilder.setIcon(IconCompat.createWithBitmap(bitmap))
            }
        }
        val caller = personBuilder.build()

        val launchIntent = launchIntentFlags(context) { intent ->
            intent.action = SELECT_FOREGROUND_NOTIFICATION_ACTION
            intent.putExtra(NOTIFICATION_ID_EXTRA, RING_NOTIFICATION_ID)
            intent.putExtra(PAYLOAD_EXTRA, payload)
        }
        val contentPendingIntent = PendingIntent.getActivity(
            context,
            RING_NOTIFICATION_ID,
            launchIntent,
            pendingIntentFlags(),
        )

        val declineIntent = Intent().apply {
            setClassName(context, ACTION_RECEIVER_CLASS)
            action = ACTION_TAPPED
            putExtra(NOTIFICATION_ID_EXTRA, RING_NOTIFICATION_ID)
            putExtra(ACTION_ID_EXTRA, "decline")
            putExtra(CANCEL_NOTIFICATION_EXTRA, true)
            putExtra(PAYLOAD_EXTRA, payload)
        }
        val declinePendingIntent = PendingIntent.getBroadcast(
            context,
            RING_NOTIFICATION_ID * 16,
            declineIntent,
            pendingIntentFlags(),
        )

        val answerIntent = launchIntentFlags(context) { intent ->
            intent.action = SELECT_FOREGROUND_NOTIFICATION_ACTION
            intent.putExtra(NOTIFICATION_ID_EXTRA, RING_NOTIFICATION_ID)
            intent.putExtra(ACTION_ID_EXTRA, "accept")
            intent.putExtra(CANCEL_NOTIFICATION_EXTRA, true)
            intent.putExtra(PAYLOAD_EXTRA, payload)
        }
        val answerPendingIntent = PendingIntent.getActivity(
            context,
            RING_NOTIFICATION_ID * 16 + 1,
            answerIntent,
            pendingIntentFlags(),
        )

        val notification: Notification = NotificationCompat.Builder(context, channelId)
            .setContentTitle(title)
            .setContentText(callerName)
            // Not applicationInfo.icon: a small icon renders as an alpha-mask
            // silhouette, which the launcher icon was never drawn for.
            // Resolved by name because this module can't see the app
            // module's generated R class — the app depends on this plugin,
            // not the other way round.
            .setSmallIcon(smallIconResId(context))
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(contentPendingIntent)
            .setFullScreenIntent(contentPendingIntent, true)
            .setStyle(
                NotificationCompat.CallStyle.forIncomingCall(
                    caller,
                    declinePendingIntent,
                    answerPendingIntent,
                ),
            )
            .build()

        NotificationManagerCompat.from(context).notify(RING_NOTIFICATION_ID, notification)
    }

    private fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(RING_NOTIFICATION_ID)
    }

    private fun smallIconResId(context: Context): Int = context.resources.getIdentifier(
        SMALL_ICON_NAME,
        "drawable",
        context.packageName,
    )

    private fun launchIntentFlags(context: Context, configure: (Intent) -> Unit): Intent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(context.packageName)
            }
        configure(intent)
        return intent
    }

    private fun pendingIntentFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private companion object {
        const val RING_NOTIFICATION_ID = 4002
        const val NOTIFICATION_ID_EXTRA = "notificationId"
        const val PAYLOAD_EXTRA = "payload"
        const val ACTION_ID_EXTRA = "actionId"
        const val CANCEL_NOTIFICATION_EXTRA = "cancelNotification"
        const val SELECT_FOREGROUND_NOTIFICATION_ACTION = "SELECT_FOREGROUND_NOTIFICATION"
        const val FALLBACK_CALLER_NAME = "Incoming call"
        const val SMALL_ICON_NAME = "ic_stat_zuno_mark"
        const val ACTION_TAPPED =
            "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver.ACTION_TAPPED"
        const val ACTION_RECEIVER_CLASS =
            "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"
    }
}
