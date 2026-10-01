package im.zuno.chat.zuno_call_style

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONObject

// Builds and posts the incoming-call ring notification using Android's
// NotificationCompat.CallStyle — unavailable through
// flutter_local_notifications (this app's pinned 22.3.0 has no CallStyle
// API), so this posts directly via NotificationManagerCompat instead of
// going through the plugin's own Notification.Builder.
//
// The channel (already registered by CallNotificationService.initialize())
// and notification id (4002, matching _ringNotificationId in
// lib/core/calls/platform/incoming_call_presenter.dart) are unchanged —
// only how the Notification object for that id gets built.
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
class ZunoCallStylePlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var assets: FlutterPlugin.FlutterAssets
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        assets = binding.flutterAssets
        channel = MethodChannel(binding.binaryMessenger, "zuno/call_style")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachTo(binding)
        silenceIfAnswered(binding.activity.intent)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachTo(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachFromActivity()
    }

    override fun onDetachedFromActivity() {
        detachFromActivity()
    }

    override fun onNewIntent(intent: Intent): Boolean {
        silenceIfAnswered(intent)
        return false
    }

    private fun attachTo(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
    }

    private fun detachFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    private fun silenceIfAnswered(intent: Intent?) {
        if (intent == null) return
        val answered = RingDecisions.answered(
            intent.action,
            intent.getIntExtra(NOTIFICATION_ID_EXTRA, -1),
            intent.getStringExtra(ACTION_ID_EXTRA),
        )
        if (!answered) return
        val callId = try {
            JSONObject(intent.getStringExtra(PAYLOAD_EXTRA) ?: "").opt("callId") as? String
        } catch (e: Exception) {
            null
        }
        IncomingRing.stopFor(context, callId, takeDownNotification = false)
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
                val callId = (call.arguments as? Map<*, *>)?.get("callId") as? String
                result.success(IncomingRing.dismiss(context, callId))
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
            intent.putExtra(ACTION_ID_EXTRA, RingDecisions.ANSWER_ACTION_ID)
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
            .setTimeoutAfter(RingDecisions.RING_TIMEOUT_MS)
            .setContentIntent(contentPendingIntent)
            .setFullScreenIntent(contentPendingIntent, true)
            .setDeleteIntent(IncomingRing.dismissIntent(context, callId))
            .setStyle(
                NotificationCompat.CallStyle.forIncomingCall(
                    caller,
                    declinePendingIntent,
                    answerPendingIntent,
                ),
            )
            .build()

        val ring = RingPlan.from(args)
        IncomingRing.present(
            context,
            callId,
            notification,
            ring.ringtoneAsset?.let { assets.getAssetFilePathByName(it) },
            ring.vibrationPattern,
        )
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

    private fun pendingIntentFlags(): Int =
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    private companion object {
        const val RING_NOTIFICATION_ID = IncomingRing.NOTIFICATION_ID
        const val NOTIFICATION_ID_EXTRA = "notificationId"
        const val PAYLOAD_EXTRA = "payload"
        const val ACTION_ID_EXTRA = "actionId"
        const val CANCEL_NOTIFICATION_EXTRA = "cancelNotification"
        const val SELECT_FOREGROUND_NOTIFICATION_ACTION = RingDecisions.SELECT_NOTIFICATION_ACTION
        const val FALLBACK_CALLER_NAME = "Incoming call"
        const val SMALL_ICON_NAME = "ic_stat_zuno_mark"
        const val ACTION_TAPPED =
            "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver.ACTION_TAPPED"
        const val ACTION_RECEIVER_CLASS =
            "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"
    }
}
