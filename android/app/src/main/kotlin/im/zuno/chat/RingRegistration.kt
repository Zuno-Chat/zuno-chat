package im.zuno.chat

import android.content.Context
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.util.Base64

object RingRegistration {
    const val CHANNEL = "zuno/ring"
    const val TOKEN_EVENT = "token"
    const val KEY_MISMATCH_EVENT = "keyMismatch"
    private const val PREFERENCES = "zuno_ring_registration"
    private const val EVENTS_KEY = "events"
    private const val OFFSET_KEY = "server_offset_ms"
    private const val USER_KEY = "user_id"
    private const val TAG = "RingRegistration"
    private const val SEPARATOR = ","
    private val handoff = RingPushHandoff()

    fun status(token: String?, keys: RingKeys?): Map<String, Any?> = mapOf(
        "token" to token,
        "environment" to "production",
        "kid" to (keys?.kid ?: 0L),
        "key" to (keys?.let { encode(it.key) } ?: ""),
        "rings" to (keys != null),
    )

    fun withEvent(stored: String?, event: String): String =
        (eventsIn(stored) + event).distinct().joinToString(SEPARATOR)

    fun eventsIn(stored: String?): List<String> =
        stored?.split(SEPARATOR)?.filter { it.isNotEmpty() } ?: emptyList()

    fun keyStore(context: Context): RingKeyStore =
        RingKeyStore(KeystoreRingKeyVault(context.applicationContext))

    fun userId(context: Context): String? = preferences(context).getString(USER_KEY, null)

    fun judgeAndHandOff(
        context: Context,
        messageId: String?,
        data: Map<String, String?>,
    ): RingPushOutcome {
        val judgedAtMs = SystemClock.elapsedRealtime()
        return judge(context, data).also { handoff.keep(messageId, it, judgedAtMs) }
    }

    fun takeOrJudge(
        context: Context,
        messageId: String?,
        data: Map<String, String?>,
    ): RingPushOutcome = handoff.takeOrJudge(messageId, SystemClock.elapsedRealtime()) {
        judge(context, data)
    }

    fun judge(context: Context, data: Map<String, String?>): RingPushOutcome {
        val keys = (keyStore(context).load() as? RingKeysRead.Ready)?.keys
        val now = System.currentTimeMillis()
        val opened = RingBlob.open(data) { kid -> keys?.keyFor(kid, now) }
        val outcome = RingPushDecision.decide(opened, now, serverOffsetMs(context))
        if (outcome == RingPushOutcome.ReRegister) {
            Log.i(TAG, "Ring push under an unknown key, registering again")
            queueEvent(context, KEY_MISMATCH_EVENT)
        }
        return outcome
    }

    fun serverOffsetMs(context: Context): Long? {
        val prefs = preferences(context)
        return if (prefs.contains(OFFSET_KEY)) prefs.getLong(OFFSET_KEY, 0L) else null
    }

    @Synchronized
    fun queueEvent(context: Context, event: String) {
        val prefs = preferences(context)
        prefs.edit().putString(
            EVENTS_KEY,
            withEvent(prefs.getString(EVENTS_KEY, null), event),
        ).commit()
    }

    @Synchronized
    private fun takeEvents(context: Context): List<String> {
        val prefs = preferences(context)
        val events = eventsIn(prefs.getString(EVENTS_KEY, null))
        prefs.edit().remove(EVENTS_KEY).commit()
        return events
    }

    fun handler(context: Context): MethodChannel.MethodCallHandler {
        val app = context.applicationContext
        return MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "status" -> {
                    val keys = if (RingBlob.isSupported) {
                        (keyStore(app).current() as? RingKeysRead.Ready)?.keys
                    } else {
                        null
                    }
                    result.success(status(FcmPushKeys.registeredToken(app), keys))
                }

                "rotateKey" -> result.success(
                    keyStore(app).rotate()?.let { mapOf("kid" to it.kid, "key" to encode(it.key)) },
                )

                "ackKey" -> {
                    call.argument<Number>("kid")?.toLong()?.let {
                        keyStore(app).acknowledge(it, System.currentTimeMillis())
                    }
                    call.argument<Number>("serverOffsetMs")?.toLong()?.let {
                        preferences(app).edit().putLong(OFFSET_KEY, it).commit()
                    }
                    result.success(null)
                }

                "takeEvents" -> result.success(takeEvents(app).map { mapOf("type" to it) })

                "setSession" -> {
                    val prefs = preferences(app)
                    if (call.argument<Boolean>("signedIn") == false) {
                        keyStore(app).delete()
                        prefs.edit().remove(OFFSET_KEY).remove(USER_KEY).commit()
                    } else {
                        call.argument<String>("userId")?.let {
                            prefs.edit().putString(USER_KEY, it).commit()
                        }
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun encode(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)
}
