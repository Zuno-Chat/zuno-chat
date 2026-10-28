package im.zuno.chat

import android.app.NotificationManager
import android.os.SystemClock
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import im.zuno.chat.zuno_notifications.FlutterStore
import im.zuno.chat.zuno_notifications.PushNotice
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
                FcmPushHandling.DART -> ackedAtElapsedMs = deliverToDart(
                    "push",
                    mapOf("data" to HashMap(message.data), "appInFront" to appInFront),
                    messageId,
                )

                FcmPushHandling.RING -> {
                    val outcome = RingRegistration.takeOrJudge(this, messageId, message.data)
                    when (outcome) {
                        is RingPushOutcome.Ring -> ackedAtElapsedMs = deliverToDart(
                            "ring",
                            ringArgs(outcome, appInFront),
                            messageId,
                        )

                        is RingPushOutcome.Drop ->
                            Log.i(TAG, "Ring push $messageId dropped: ${outcome.reason}")

                        RingPushOutcome.ReRegister -> Unit
                    }
                }

                FcmPushHandling.CLEAR_MESSAGES -> clearMessageNotifications()

                FcmPushHandling.NOTHING -> Log.d(TAG, "Badge push $messageId needs nothing")
            }
        } finally {
            messageId?.let { PushWakeLock.release(applicationContext, it) }
            PushDeliveryLog.handled(
                applicationContext,
                messageId,
                PushServiceTiming(startedAtElapsedMs, handling, ackedAtElapsedMs),
            )
        }
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onNewToken(token: String) {
        val registered = FcmPushKeys.registeredToken(applicationContext)
        if (!FcmPushKeys.shouldForwardToken(registered, token)) return
        Log.i(TAG, "FCM token changed, updating the push registration")
        RingRegistration.queueEvent(applicationContext, RingRegistration.TOKEN_EVENT)
        awaitHandled(
            FcmRouter.deliver(applicationContext, "token", mapOf("token" to token), "token"),
            "token refresh",
        )
    }

    override fun onDeletedMessages() {
        Log.w(TAG, "FCM dropped messages it could not deliver")
        PushNotice.postMissed(applicationContext)
    }

    private fun deliverToDart(method: String, args: Map<String, Any?>, messageId: String?): Long? {
        val done = FcmRouter.deliver(applicationContext, method, args, messageId ?: method)
        return if (awaitHandled(done, "$method $messageId")) SystemClock.elapsedRealtime() else null
    }

    private fun ringArgs(outcome: RingPushOutcome.Ring, appInFront: Boolean): Map<String, Any?> =
        mapOf(
            "room" to outcome.ring.room,
            "call" to outcome.ring.call,
            "caller" to outcome.ring.caller,
            "cname" to outcome.ring.cname,
            "rname" to outcome.ring.rname,
            "kind" to outcome.ring.kind.wire,
            "appInFront" to appInFront,
            "ringMs" to outcome.ringMs,
        )

    private fun clearMessageNotifications() {
        Log.i(TAG, "Badge push says everything is read, clearing chat notifications")
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val shown = manager.activeNotifications.map {
                ShownNotification(it.id, it.notification.channelId)
            }
            FcmBadgeDecision.messageNotificationIds(shown).forEach { manager.cancel(it) }
        } catch (e: Exception) {
            CaughtErrors.record(this, "fcm clear chat notifications", e)
        }
        try {
            FlutterStore.preferences(this).edit().remove(FlutterStore.THREADS).apply()
        } catch (e: Exception) {
            CaughtErrors.record(this, "fcm forget notification threads", e)
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
    }
}
