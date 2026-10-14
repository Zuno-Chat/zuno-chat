package im.zuno.chat.zuno_notifications

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import androidx.core.app.Person
import androidx.core.content.LocusIdCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

object ConversationShortcut {
    const val CATEGORY = "android.shortcut.conversation"
    private const val TAG = "ZunoNotifications"

    fun push(
        context: Context,
        roomId: String,
        label: String,
        isGroup: Boolean,
        avatarBytes: ByteArray?,
    ) {
        try {
            val icon = avatarBytes
                ?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                ?.let { IconCompat.createWithAdaptiveBitmap(it) }
                ?: IconCompat.createWithResource(context, context.applicationInfo.icon)
            val name = label.ifBlank { context.getString(R.string.notificationsFallbackChatName) }
            val person = Person.Builder()
                .setName(name)
                .setKey(roomId)
                .apply { if (!isGroup) setIcon(icon) }
                .build()
            val shortcut = ShortcutInfoCompat.Builder(context, roomId)
                .setShortLabel(name)
                .setLongLived(true)
                .setIsConversation()
                .setPerson(person)
                .setIcon(icon)
                .setIntent(RoomLaunchIntent.forRoom(context, roomId))
                .setCategories(setOf(CATEGORY))
                .setLocusId(LocusIdCompat(roomId))
                .build()
            ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
        } catch (e: Exception) {
            Log.w(TAG, "Could not publish the conversation shortcut", e)
        }
    }

    fun retain(context: Context, roomIds: Collection<String>) {
        try {
            val kept = roomIds.toSet()
            val left = ShortcutManagerCompat.getShortcuts(
                context,
                ShortcutManagerCompat.FLAG_MATCH_DYNAMIC or ShortcutManagerCompat.FLAG_MATCH_CACHED,
            )
                .filter { it.categories?.contains(CATEGORY) == true && it.id !in kept }
                .map { it.id }
            if (left.isNotEmpty()) ShortcutManagerCompat.removeLongLivedShortcuts(context, left)
        } catch (e: Exception) {
            Log.w(TAG, "Could not remove the shortcuts of rooms left", e)
        }
    }

    fun exists(context: Context, roomId: String): Boolean = try {
        ShortcutManagerCompat.getShortcuts(
            context,
            ShortcutManagerCompat.FLAG_MATCH_DYNAMIC or
                ShortcutManagerCompat.FLAG_MATCH_PINNED or
                ShortcutManagerCompat.FLAG_MATCH_CACHED,
        ).any { it.id == roomId }
    } catch (e: Exception) {
        false
    }
}
