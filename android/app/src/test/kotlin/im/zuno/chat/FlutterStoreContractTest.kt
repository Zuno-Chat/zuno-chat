package im.zuno.chat

import im.zuno.chat.zuno_notifications.CachedRoom
import im.zuno.chat.zuno_notifications.FlutterStore
import im.zuno.chat.zuno_notifications.PushNoticeDecision
import im.zuno.chat.zuno_notifications.RememberedRing
import im.zuno.chat.zuno_notifications.RingDecisions
import java.lang.reflect.Modifier
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class FlutterStoreContractTest {
    private val contract = ContractFixtures.load("flutter_store_v1.json")
    private val prefix = contract.getString("prefix")
    private val keys = contract.getJSONObject("keys")
    private val ringingCall = contract.getJSONObject("ringingCall")

    private val nativeKeys = mapOf(
        "ringingCall" to FlutterStore.RINGING_CALL,
        "resolvedCallPrefix" to FlutterStore.RESOLVED_CALL_PREFIX,
        "roomCache" to FlutterStore.ROOM_CACHE,
        "threads" to FlutterStore.THREADS,
        "recentDeliveries" to FlutterStore.RECENT_DELIVERIES,
        "fcmToken" to FlutterStore.FCM_TOKEN,
        "notificationPreview" to FlutterStore.NOTIFICATION_PREVIEW,
        "notifyMe" to FlutterStore.NOTIFY_ME,
        "messageTone" to FlutterStore.MESSAGE_TONE,
        "messageVibration" to FlutterStore.MESSAGE_VIBRATION,
        "ringtone" to FlutterStore.RINGTONE,
        "callVibration" to FlutterStore.CALL_VIBRATION,
    )

    private fun JSONObject.keyNames(): Set<String> = keys().asSequence().toSet()

    @Test
    fun `native code opens Dart's preferences file under Dart's prefix`() {
        assertEquals(contract.getString("file"), FlutterStore.FILE)
        assertEquals(prefix, FlutterStore.PREFIX)
    }

    @Test
    fun `every key native code shares with Dart is the prefixed fixture key`() {
        assertEquals(keys.keyNames(), nativeKeys.keys)
        for ((name, key) in nativeKeys) assertEquals(name, prefix + keys.getString(name), key)
    }

    @Test
    fun `native code keeps no Dart key the fixture leaves out`() {
        val declared = FlutterStore::class.java.declaredFields
            .filter { Modifier.isStatic(it.modifiers) && it.type == String::class.java }
            .map { it.get(null) as String }
            .filter { it.startsWith(FlutterStore.PREFIX) && it != FlutterStore.PREFIX }

        assertEquals(nativeKeys.values.toSet(), declared.toSet())
    }

    @Test
    fun `native code reads Dart's hidden-preview and mentions-only values`() {
        val values = contract.getJSONObject("values")

        assertEquals(values.getString("previewHidden"), FlutterStore.PREVIEW_HIDDEN)
        assertEquals(values.getString("notifyMeMentionsOnly"), FlutterStore.NOTIFY_ME_MENTIONS_ONLY)
    }

    private val fixtureRing = RememberedRing(
        roomId = ringingCall.getString("roomId"),
        callId = ringingCall.getString("callId"),
        callerId = ringingCall.getString("callerId"),
        isVideo = ringingCall.getBoolean("isVideo"),
        postedAtMs = ringingCall.getLong("postedAt"),
    )

    @Test
    fun `the ring record native code writes has exactly the fields Dart reads`() {
        val written = JSONObject(fixtureRing.record())

        assertEquals(ringingCall.keyNames(), written.keyNames())
        for (key in ringingCall.keyNames()) {
            assertEquals(key, ringingCall.get(key), written.get(key))
        }
    }

    @Test
    fun `native code reads back the ring record in the shared format`() {
        assertEquals(fixtureRing, RememberedRing.parse(ringingCall.toString()))
    }

    @Test
    fun `native code finds a call Dart marked resolved`() {
        val resolved = contract.getJSONObject("resolvedCall")
        val callId = resolved.getString("callId")
        val at = resolved.getLong("at")
        val key = prefix + keys.getString("resolvedCallPrefix") + callId
        val stored = mapOf<String, Any?>(key to at)

        assertEquals(setOf(callId), RingDecisions.resolvedCallIds(stored, at))
    }

    @Test
    fun `native code reads the room cache Dart writes`() {
        val cache = contract.getJSONObject("roomCache")
        val rooms = cache.getJSONArray("rooms")
        val expected = (0 until rooms.length()).map { rooms.getJSONObject(it) }.associate {
            it.getString("id") to CachedRoom(it.getString("name"), it.getBoolean("isDirect"))
        }

        assertEquals(expected, PushNoticeDecision.parseRoomCache(cache.getString("encoded")))
    }

    @Test
    fun `native code logs a delivery in the line Dart reads`() {
        val logged = contract.getJSONObject("delivery")
        val delivery = PushDelivery(
            receivedAtMs = logged.getLong("receivedAtMs"),
            sentAtMs = logged.getLong("sentAtMs"),
            originalPriority = logged.getString("originalPriority"),
            deliveredPriority = logged.getString("deliveredPriority"),
            deviceIdle = logged.getBoolean("deviceIdle"),
            standbyBucket = logged.getInt("standbyBucket"),
            receiverMs = logged.getLong("receiverMs"),
            noticePosted = logged.getBoolean("noticePosted"),
            serviceStartMs = logged.getLong("serviceStartMs"),
            handling = FcmPushHandling.entries.single { it.wire == logged.getString("handling") },
            ackMs = logged.getLong("ackMs"),
        )

        assertEquals(logged.getString("line"), PushDeliveryLog.lineFor(delivery))
    }
}
