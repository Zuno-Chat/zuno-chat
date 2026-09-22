package im.zuno.chat.zuno_notifications

import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutManagerCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

class ZunoNotificationsPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var conversations: MethodChannel
    private lateinit var wakeLocks: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        PushNotice.liveEngines.incrementAndGet()
        context = binding.applicationContext
        conversations = MethodChannel(binding.binaryMessenger, CONVERSATIONS_CHANNEL)
        conversations.setMethodCallHandler(this)
        wakeLocks = MethodChannel(binding.binaryMessenger, WAKE_LOCK_CHANNEL)
        wakeLocks.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        PushNotice.liveEngines.decrementAndGet()
        conversations.setMethodCallHandler(null)
        wakeLocks.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "pushConversationShortcut" -> {
                val roomId = call.argument<String>("roomId")
                val label = call.argument<String>("label")
                if (roomId == null || label == null) {
                    result.error("bad_args", "roomId and label are required", null)
                    return
                }
                ConversationShortcut.push(
                    context,
                    roomId,
                    label,
                    isGroup = call.argument<Boolean>("isGroup") == true,
                    avatarBytes = call.argument<ByteArray>("avatarBytes"),
                )
                result.success(null)
            }
            "publishNotificationImage" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"
                if (bytes == null) {
                    result.error("bad_args", "bytes are required", null)
                    return
                }
                result.success(publishImage(bytes, mimeType))
            }
            "removeConversationShortcut" -> {
                val roomId = call.argument<String>("roomId")
                if (roomId != null) {
                    ShortcutManagerCompat.removeLongLivedShortcuts(context, listOf(roomId))
                }
                result.success(null)
            }
            "acquire" -> {
                val tag = call.argument<String>("tag") ?: DEFAULT_TAG
                val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: DEFAULT_TIMEOUT_MS
                acquire(tag, timeoutMs)
                result.success(null)
            }
            "release" -> {
                release(call.argument<String>("tag") ?: DEFAULT_TAG)
                result.success(null)
            }
            "takePushNotice" -> {
                val roomId = call.argument<String>("roomId")
                val eventId = call.argument<String>("eventId")
                result.success(roomId != null && eventId != null && PushNotice.take(roomId, eventId))
            }
            else -> result.notImplemented()
        }
    }

    private fun publishImage(bytes: ByteArray, mimeType: String): String? {
        return try {
            val dir = File(context.cacheDir, IMAGE_DIR).apply { mkdirs() }
            pruneOldImages(dir)
            val extension = when (mimeType) {
                "image/png" -> "png"
                "image/webp" -> "webp"
                "image/gif" -> "gif"
                else -> "jpg"
            }
            val file = File(dir, "${System.currentTimeMillis()}_${imageCounter.incrementAndGet()}.$extension")
            file.writeBytes(bytes)
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.$AUTHORITY_SUFFIX", file)
            context.grantUriPermission(SYSTEM_UI, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            uri.toString()
        } catch (e: Exception) {
            Log.w(TAG, "Could not publish the notification image", e)
            null
        }
    }

    private fun pruneOldImages(dir: File) {
        val cutoff = System.currentTimeMillis() - MAX_IMAGE_AGE_MS
        dir.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.delete() }
    }

    @Synchronized
    private fun acquire(tag: String, timeoutMs: Long) {
        release(tag)
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            held[tag] = powerManager
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "zuno:$tag")
                .apply {
                    setReferenceCounted(false)
                    acquire(timeoutMs)
                }
        } catch (e: Exception) {
            Log.w(TAG, "Could not take wake lock $tag", e)
        }
    }

    @Synchronized
    private fun release(tag: String) {
        try {
            held.remove(tag)?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Could not release wake lock $tag", e)
        }
    }

    private companion object {
        const val TAG = "ZunoNotifications"
        const val CONVERSATIONS_CHANNEL = "zuno/conversations"
        const val WAKE_LOCK_CHANNEL = "zuno/wake_lock"
        const val DEFAULT_TAG = "notification"
        const val DEFAULT_TIMEOUT_MS = 30_000L
        const val IMAGE_DIR = "notification_images"
        const val AUTHORITY_SUFFIX = "zuno_notifications"
        const val SYSTEM_UI = "com.android.systemui"
        const val MAX_IMAGE_AGE_MS = 24 * 60 * 60 * 1000L
        val held = HashMap<String, PowerManager.WakeLock>()
        val imageCounter = AtomicInteger()
    }
}
