package im.zuno.chat

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.core.content.IntentCompat
import im.zuno.chat.InboundShareDecision.SharedFile

class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val files = sharedFiles(intent)
        if (InboundShareDecision.payload(text, files) != null) {
            startActivity(forwardIntent(text, files))
        }
        finish()
    }

    private fun sharedFiles(intent: Intent): List<SharedFile> {
        val perItemTypes = intent.getStringArrayListExtra(Intent.EXTRA_MIME_TYPES)
        return sharedUris(intent).mapIndexed { i, uri ->
            val raw = uri.toString()
            SharedFile(
                uri = raw,
                name = InboundShareDecision.fileName(displayName(uri), raw),
                mimeType = InboundShareDecision.mimeTypeFor(
                    perItemTypes?.getOrNull(i),
                    runCatching { contentResolver.getType(uri) }.getOrNull(),
                    intent.type,
                ),
            )
        }
    }

    private fun sharedUris(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND ->
            listOfNotNull(IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java))
        Intent.ACTION_SEND_MULTIPLE ->
            IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        else -> emptyList()
    }

    private fun displayName(uri: Uri): String? = runCatching {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }.getOrNull()

    private fun forwardIntent(text: String?, files: List<SharedFile>): Intent =
        Intent(this, MainActivity::class.java).apply {
            action = ACTION_INBOUND_SHARE
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            putExtra(EXTRA_SHARE_TEXT, text)
            putStringArrayListExtra(EXTRA_SHARE_URIS, ArrayList(files.map { it.uri }))
            putStringArrayListExtra(EXTRA_SHARE_NAMES, ArrayList(files.map { it.name }))
            putStringArrayListExtra(EXTRA_SHARE_MIME_TYPES, ArrayList(files.map { it.mimeType ?: "" }))
            val uris = files.map { Uri.parse(it.uri) }
            if (uris.isNotEmpty()) {
                val clip = ClipData.newRawUri(null, uris.first())
                uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
                clipData = clip
            }
        }

    companion object {
        const val ACTION_INBOUND_SHARE = "im.zuno.chat.action.INBOUND_SHARE"
        private const val EXTRA_SHARE_TEXT = "share_text"
        private const val EXTRA_SHARE_URIS = "share_uris"
        private const val EXTRA_SHARE_NAMES = "share_names"
        private const val EXTRA_SHARE_MIME_TYPES = "share_mime_types"

        fun channelPayload(intent: Intent?): Map<String, Any?>? {
            if (intent?.action != ACTION_INBOUND_SHARE) return null
            val uris = intent.getStringArrayListExtra(EXTRA_SHARE_URIS).orEmpty()
            val names = intent.getStringArrayListExtra(EXTRA_SHARE_NAMES).orEmpty()
            val types = intent.getStringArrayListExtra(EXTRA_SHARE_MIME_TYPES).orEmpty()
            val files = uris.mapIndexed { i, uri ->
                SharedFile(
                    uri,
                    names.getOrNull(i) ?: "shared",
                    types.getOrNull(i)?.takeIf { it.isNotEmpty() },
                )
            }
            return InboundShareDecision.payload(intent.getStringExtra(EXTRA_SHARE_TEXT), files)
        }
    }
}
