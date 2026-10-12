package im.zuno.chat

object OutboundShareDecision {
    private const val ANY = "*/*"

    fun intentType(mimeTypes: List<String?>): String {
        if (mimeTypes.isEmpty() || !mimeTypes.all(::isSpecific)) return ANY
        val types = mimeTypes.filterNotNull().distinct()
        if (types.size == 1) return types.single()
        val families = types.map { it.substringBefore('/') }.distinct()
        return if (families.size == 1) "${families.single()}/*" else ANY
    }

    private fun isSpecific(mime: String?): Boolean =
        mime != null && mime.substringBefore('/', "").isNotEmpty() &&
            mime.substringAfter('/', "").isNotEmpty() && !mime.contains('*')
}
