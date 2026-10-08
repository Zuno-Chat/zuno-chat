package im.zuno.chat.zuno_notifications

import android.content.Context
import android.content.Intent

object RoomLaunchIntent {
    const val EXTRA_ROOM_ID = "room_id"

    fun forRoom(context: Context, roomId: String): Intent =
        AppLaunchIntent.of(context, Intent.ACTION_VIEW).putExtra(EXTRA_ROOM_ID, roomId)
}
