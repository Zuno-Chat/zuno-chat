package im.zuno.chat

import java.net.URLDecoder

object InboundShareDecision {
    data class SharedFile(val uri: String, val name: String, val mimeType: String?)

    fun mimeTypeFor(perItem: String?, resolved: String?, intentType: String?): String? =
        listOf(perItem, resolved, intentType).firstOrNull { isSpecific(it) }

    private fun isSpecific(mime: String?): Boolean =
        !mime.isNullOrBlank() && !mime.contains('*')

    fun fileName(displayName: String?, uri: String): String {
        val fromDisplay = displayName?.trim().orEmpty()
        if (fromDisplay.isNotEmpty()) return safeFileName(fromDisplay)
        val path = uri.substringBefore('?').substringAfter("://", "")
        val lastSegment = path.trimEnd('/').substringAfterLast('/').trim()
        val decoded = runCatching { URLDecoder.decode(lastSegment, "UTF-8") }.getOrDefault(lastSegment)
        return safeFileName(decoded)
    }

    fun safeFileName(name: String): String {
        val cleaned = name.replace('/', '_').replace('\\', '_')
        return if (cleaned.isEmpty() || cleaned == "." || cleaned == "..") "shared" else cleaned
    }

    fun payload(text: String?, files: List<SharedFile>): Map<String, Any?>? {
        val cleanText = text?.takeIf { it.isNotBlank() }
        if (cleanText == null && files.isEmpty()) return null
        return mapOf(
            "text" to cleanText,
            "files" to files.map {
                mapOf("uri" to it.uri, "name" to it.name, "mimeType" to it.mimeType)
            },
        )
    }
}
