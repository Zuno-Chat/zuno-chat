package im.zuno.chat.zuno_vibration

object VibrationAmplitudes {
    private const val FULL = 255

    fun forPattern(pattern: LongArray): IntArray =
        IntArray(pattern.size) { if (it % 2 == 1) FULL else 0 }
}
