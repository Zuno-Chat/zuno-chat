package im.zuno.chat

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import kotlin.math.max

object VideoTools {
    private val executor = Executors.newSingleThreadExecutor()
    private val thumbnailExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private const val MIN_SAMPLE_BUFFER = 2 shl 20

    fun probe(path: String, onResult: (Map<String, Any?>?) -> Unit) {
        executor.execute {
            val result = try { probeNow(path) } catch (error: Exception) { null }
            mainHandler.post { onResult(result) }
        }
    }

    fun remux(input: String, output: String, onResult: (Boolean) -> Unit) {
        executor.execute {
            val result = try { remuxNow(input, output) } catch (error: Exception) { false }
            mainHandler.post { onResult(result) }
        }
    }

    fun thumbnail(path: String, maxDimension: Int, quality: Int, onResult: (Map<String, Any>?) -> Unit) {
        thumbnailExecutor.execute {
            val result = try {
                thumbnailNow(path, maxDimension, quality)
            } catch (error: Exception) {
                null
            } catch (error: OutOfMemoryError) {
                null
            }
            mainHandler.post { onResult(result) }
        }
    }

    private fun probeNow(path: String): Map<String, Any?>? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: return null
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: return null
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val rotated = rotation % 180 != 0
            val (videoCodec, audioCodec) = trackCodecs(path)
            return mapOf(
                "width" to if (rotated) height else width,
                "height" to if (rotated) width else height,
                "bitrate" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull(),
                "durationMs" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toIntOrNull(),
                "videoCodec" to videoCodec,
                "audioCodec" to audioCodec,
            )
        } finally {
            retriever.release()
        }
    }

    private fun trackCodecs(path: String): Pair<String?, String?> {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            var video: String? = null
            var audio: String? = null
            for (i in 0 until extractor.trackCount) {
                val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
                if (video == null && mime.startsWith("video/")) video = mime
                else if (audio == null && mime.startsWith("audio/")) audio = mime
            }
            return video to audio
        } finally {
            extractor.release()
        }
    }

    private fun remuxNow(input: String, output: String): Boolean {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            extractor.setDataSource(input)
            muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val trackMap = HashMap<Int, Int>()
            var bufferSize = MIN_SAMPLE_BUFFER
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                if (mime.startsWith("video/") && format.containsKey(MediaFormat.KEY_ROTATION)) {
                    muxer.setOrientationHint(format.getInteger(MediaFormat.KEY_ROTATION))
                }
                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    bufferSize = max(bufferSize, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
                extractor.selectTrack(i)
                trackMap[i] = muxer.addTrack(format)
            }
            if (trackMap.isEmpty()) return false
            muxer.start()
            val buffer = ByteBuffer.allocateDirect(bufferSize)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                info.offset = 0
                info.size = size
                info.presentationTimeUs = extractor.sampleTime
                info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                } else {
                    0
                }
                muxer.writeSampleData(trackMap.getValue(extractor.sampleTrackIndex), buffer, info)
                extractor.advance()
            }
            muxer.stop()
            return true
        } finally {
            extractor.release()
            try {
                muxer?.release()
            } catch (error: Exception) {
            }
        }
    }

    private fun thumbnailNow(path: String, maxDimension: Int, quality: Int): Map<String, Any>? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, maxDimension, maxDimension)
            } else {
                retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            } ?: return null
            return ImageResizer.encodeScaled(frame, maxDimension, quality, png = false)
        } finally {
            retriever.release()
        }
    }
}
