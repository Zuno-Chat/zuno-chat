package im.zuno.chat.zuno_notifications

import android.content.Context
import android.content.Intent

object RoomLaunchIntent {
    const val EXTRA_ROOM_ID = "room_id"

    fun forRoom(context: Context, roomId: String): Intent =
        (context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(context.packageName)
            }).apply {
            action = Intent.ACTION_VIEW
            putExtra(EXTRA_ROOM_ID, roomId)
        }
}
