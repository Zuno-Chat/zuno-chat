package im.zuno.chat.zuno_notifications

import android.app.PendingIntent
import android.content.Context
import android.content.Intent

object AppLaunchIntent {
    const val TO_RUNNING_APP =
        Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP

    fun of(context: Context, action: String): Intent = (
        context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(context.packageName)
            }
        ).apply {
        this.action = action
        addFlags(TO_RUNNING_APP)
    }

    fun pending(context: Context, requestCode: Int): PendingIntent = PendingIntent.getActivity(
        context,
        requestCode,
        of(context, Intent.ACTION_MAIN),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}
