package im.zuno.chat

import java.net.URLDecoder

object InboundShareDecision {
    private const val CONTENT_SCHEME = "content"
    private const val MAX_NAME_BYTES = 255

    data class SharedFile(val uri: String, val name: String, val mimeType: String?)

    fun mayRead(scheme: String?, providerPackage: String?, ownPackage: String): Boolean =
        scheme == CONTENT_SCHEME && providerPackage != ownPackage

    fun providerAuthority(authority: String?): String? = authority?.substringAfterLast('@')

    fun mimeTypeFor(perItem: String?, resolved: String?, intentType: String?): String? =
        listOf(perItem, resolved, intentType).firstOrNull { isSpecific(it) }

    private fun isSpecific(mime: String?): Boolean = !mime.isNullOrBlank() && !mime.contains('*')

    fun fileName(displayName: String?, uri: String): String {
        val fromDisplay = displayName?.trim().orEmpty()
        if (fromDisplay.isNotEmpty()) return safeFileName(fromDisplay)
        val path = uri.substringBefore('?').substringAfter("://", "")
        val lastSegment = path.trimEnd('/').substringAfterLast('/').trim()
        val decoded = try {
            URLDecoder.decode(lastSegment, "UTF-8")
        } catch (e: IllegalArgumentException) {
            lastSegment
        }
        return safeFileName(decoded)
    }

    fun safeFileName(name: String): String {
        val cleaned = name.replace('/', '_').replace('\\', '_')
        if (cleaned.isEmpty() || cleaned == "." || cleaned == "..") return "shared"
        return fittedName(cleaned)
    }

    private fun fittedName(name: String): String {
        if (utf8Length(name) <= MAX_NAME_BYTES) return name
        val dot = name.lastIndexOf('.')
        if (dot > 0) {
            val extension = name.substring(dot)
            val stem = utf8Prefix(name.substring(0, dot), MAX_NAME_BYTES - utf8Length(extension))
            if (stem.isNotEmpty()) return stem + extension
        }
        return utf8Prefix(name, MAX_NAME_BYTES)
    }

    private fun utf8Prefix(text: String, maxBytes: Int): String {
        var bytes = 0
        var end = 0
        while (end < text.length) {
            val codePoint = text.codePointAt(end)
            bytes += utf8Width(codePoint)
            if (bytes > maxBytes) break
            end += Character.charCount(codePoint)
        }
        return text.substring(0, end)
    }

    private fun utf8Length(text: String): Int = text.toByteArray(Charsets.UTF_8).size

    private fun utf8Width(codePoint: Int): Int = when {
        codePoint < 0x80 -> 1
        codePoint < 0x800 -> 2
        codePoint < 0x10000 -> 3
        else -> 4
    }

    fun joinedText(texts: List<CharSequence?>): String? = texts
        .mapNotNull { it?.toString() }
        .filter { it.isNotBlank() }
        .distinct()
        .joinToString("\n")
        .ifEmpty { null }

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
