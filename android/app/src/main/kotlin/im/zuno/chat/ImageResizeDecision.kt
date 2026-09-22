package im.zuno.chat

import kotlin.math.max
import kotlin.math.roundToInt

object ImageResizeDecision {
    data class Size(val width: Int, val height: Int)

    fun targetSize(width: Int, height: Int, maxDimension: Int): Size {
        val longEdge = max(width, height)
        if (longEdge <= maxDimension) return Size(width, height)
        val scale = maxDimension.toDouble() / longEdge
        return Size(
            max(1, (width * scale).roundToInt()),
            max(1, (height * scale).roundToInt()),
        )
    }

    fun sampleSize(width: Int, height: Int, target: Size): Int {
        var sample = 1
        while (width / (sample * 2) >= target.width && height / (sample * 2) >= target.height) {
            sample *= 2
        }
        return sample
    }
}
