package im.zuno.chat

import android.app.NotificationManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import im.zuno.chat.zuno_notifications.PushNotice
import im.zuno.chat.zuno_notifications.PushWakeLock
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class FcmService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val startedAtElapsedMs = SystemClock.elapsedRealtime()
        val messageId = FcmPushKeys.messageId(message.messageId)
        var handling = FcmPushHandling.NOTHING
        var ackedAtElapsedMs: Long? = null
        try {
            val appInFront = PushNotice.appInFront(applicationContext)
            handling = FcmBadgeDecision.handlingFor(message.data, appInFront)
            when (handling) {
                FcmPushHandling.DART -> {
                    val args = mapOf<String, Any?>(
                        "data" to HashMap(message.data),
                        "appInFront" to appInFront,
                    )
                    val done = FcmRouter.deliver(
                        applicationContext,
                        "push",
                        args,
                        messageId ?: "push",
                    )
                    if (awaitHandled(done, "push $messageId")) {
                        ackedAtElapsedMs = SystemClock.elapsedRealtime()
                    }
                }

                FcmPushHandling.CLEAR_MESSAGES -> clearMessageNotifications()

                FcmPushHandling.NOTHING -> Log.d(TAG, "Badge push $messageId needs nothing")
            }
        } finally {
            messageId?.let { PushWakeLock.release(it) }
            PushDeliveryLog.handled(
                applicationContext,
                messageId,
                PushServiceTiming(startedAtElapsedMs, handling, ackedAtElapsedMs),
            )
        }
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onNewToken(token: String) {
        val registered = getSharedPreferences(PREFERENCES, MODE_PRIVATE).getString(TOKEN_KEY, null)
        if (!FcmPushKeys.shouldForwardToken(registered, token)) return
        Log.i(TAG, "FCM token changed, updating the push registration")
        awaitHandled(
            FcmRouter.deliver(applicationContext, "token", mapOf("token" to token), "token"),
            "token refresh",
        )
    }

    override fun onDeletedMessages() {
        Log.w(TAG, "FCM dropped messages it could not deliver")
        PushNotice.postMissed(applicationContext)
    }

    private fun clearMessageNotifications() {
        Log.i(TAG, "Badge push says everything is read, clearing chat notifications")
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val shown = manager.activeNotifications.map {
                ShownNotification(
                    it.id,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        it.notification.channelId
                    } else {
                        null
                    },
                )
            }
            FcmBadgeDecision.messageNotificationIds(shown).forEach { manager.cancel(it) }
        } catch (e: Exception) {
            Log.w(TAG, "Could not clear the chat notifications", e)
        }
        try {
            getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                .edit()
                .remove(FcmBadgeDecision.THREADS_KEY)
                .apply()
        } catch (e: Exception) {
            Log.w(TAG, "Could not forget the chat notification threads", e)
        }
    }

    private fun awaitHandled(done: CountDownLatch, what: String): Boolean {
        try {
            if (done.await(ACK_TIMEOUT_MS, TimeUnit.MILLISECONDS)) return true
            Log.w(TAG, "Still handling $what after $ACK_TIMEOUT_MS ms, letting the service go")
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        return false
    }

    private companion object {
        const val TAG = "FcmService"
        const val ACK_TIMEOUT_MS = 17_000L
        const val PREFERENCES = "FlutterSharedPreferences"
        const val TOKEN_KEY = "flutter.push.fcm.token"
    }
}
