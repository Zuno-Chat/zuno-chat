package im.zuno.chat

import android.app.Activity
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

class HandoverFileProvider : FileProvider()

object OutboundShare {
    const val CHANNEL = "zuno/share_out"
    private const val AUTHORITY_SUFFIX = ".handover"

    fun handler(activity: Activity) = MethodChannel.MethodCallHandler { call, result ->
        if (call.method != "shareFiles") {
            result.notImplemented()
            return@MethodCallHandler
        }
        try {
            activity.startActivity(
                chooser(
                    activity,
                    call.argument<List<String>>("paths").orEmpty(),
                    call.argument<List<String?>>("mimeTypes").orEmpty(),
                ),
            )
            result.success(null)
        } catch (error: RuntimeException) {
            result.error("share_failed", error.message, null)
        }
    }

    private fun chooser(context: Context, paths: List<String>, mimeTypes: List<String?>): Intent {
        require(paths.isNotEmpty()) { "nothing to share" }
        val authority = context.packageName + AUTHORITY_SUFFIX
        val uris = paths.map { FileProvider.getUriForFile(context, authority, File(it)) }
        val send = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris.single())
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE)
                .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList<Uri>(uris))
        }
        send.type = OutboundShareDecision.intentType(mimeTypes)
        send.clipData = ClipData.newRawUri(null, uris.first()).apply {
            uris.drop(1).forEach { addItem(ClipData.Item(it)) }
        }
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return Intent.createChooser(send, null).putExtra(
            Intent.EXTRA_EXCLUDE_COMPONENTS,
            arrayOf(ComponentName(context, ShareActivity::class.java)),
        )
    }
}
