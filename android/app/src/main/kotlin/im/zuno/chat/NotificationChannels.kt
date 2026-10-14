package im.zuno.chat

import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Context
import androidx.annotation.StringRes

enum class NotificationGroup(val id: String, @StringRes val title: Int) {
    CALLS("calls_group", R.string.callsChannelGroupCalls),
    BACKGROUND("background_group", R.string.notificationsChannelGroupBackground),
}

object NotificationChannels {
    fun ensure(
        context: Context,
        group: NotificationGroup,
        id: String,
        @StringRes name: Int,
        @StringRes description: Int,
        importance: Int,
    ) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannelGroup(
            NotificationChannelGroup(group.id, context.getString(group.title)),
        )
        manager.createNotificationChannel(
            NotificationChannel(id, context.getString(name), importance).apply {
                this.description = context.getString(description)
                this.group = group.id
            },
        )
    }
}
