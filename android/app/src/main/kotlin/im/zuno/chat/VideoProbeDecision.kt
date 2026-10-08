package im.zuno.chat

object VideoProbeDecision {
    data class ShownSize(val width: Int, val height: Int, val rotated: Boolean)

    fun shownSize(width: Int, height: Int, rotation: Int): ShownSize {
        val rotated = rotation % 180 != 0
        return if (rotated) ShownSize(height, width, rotated) else ShownSize(width, height, rotated)
    }
}
