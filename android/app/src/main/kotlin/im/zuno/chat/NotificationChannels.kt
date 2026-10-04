package im.zuno.chat

import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Context

enum class NotificationGroup(val id: String, val title: String) {
    CALLS("calls_group", "Calls"),
    BACKGROUND("background_group", "Background"),
}

object NotificationChannels {
    fun ensure(
        context: Context,
        group: NotificationGroup,
        id: String,
        name: String,
        description: String,
        importance: Int,
    ) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannelGroup(NotificationChannelGroup(group.id, group.title))
        manager.createNotificationChannel(
            NotificationChannel(id, name, importance).apply {
                this.description = description
                this.group = group.id
            },
        )
    }
}
