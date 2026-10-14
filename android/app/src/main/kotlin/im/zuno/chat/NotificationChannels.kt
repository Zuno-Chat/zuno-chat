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

enum class AppChannel(
    val id: String,
    val group: NotificationGroup,
    @StringRes val nameRes: Int,
    @StringRes val descriptionRes: Int,
    val importance: Int,
) {
    ONGOING_CALL(
        "calls_ongoing",
        NotificationGroup.CALLS,
        R.string.callsOngoingCall,
        R.string.callsChannelOngoingCallDescription,
        NotificationManager.IMPORTANCE_LOW,
    ),
    BACKGROUND_SYNC(
        "background_sync",
        NotificationGroup.BACKGROUND,
        R.string.notificationsChannelBackgroundSync,
        R.string.notificationsChannelBackgroundSyncDescription,
        NotificationManager.IMPORTANCE_MIN,
    ),
    LIVE_LOCATION(
        "live_location",
        NotificationGroup.BACKGROUND,
        R.string.locationLiveLocation,
        R.string.locationChannelLiveLocationDescription,
        NotificationManager.IMPORTANCE_LOW,
    ),
    UPLOADS(
        "uploads",
        NotificationGroup.BACKGROUND,
        R.string.uploadsChannelSendingFiles,
        R.string.uploadsChannelSendingFilesDescription,
        NotificationManager.IMPORTANCE_LOW,
    ),
}

object NotificationChannels {
    fun ensure(context: Context, channel: AppChannel) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannelGroup(
            NotificationChannelGroup(channel.group.id, context.getString(channel.group.title)),
        )
        manager.createNotificationChannel(
            NotificationChannel(channel.id, context.getString(channel.nameRes), channel.importance)
                .apply {
                    description = context.getString(channel.descriptionRes)
                    group = channel.group.id
                },
        )
    }

    fun refreshNames(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        AppChannel.entries
            .filter { manager.getNotificationChannel(it.id) != null }
            .forEach { ensure(context, it) }
    }
}
