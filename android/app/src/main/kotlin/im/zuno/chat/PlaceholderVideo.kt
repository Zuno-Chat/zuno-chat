package im.zuno.chat

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.MethodCallHandlerImpl
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import io.flutter.embedding.engine.FlutterEngine
import java.nio.ByteBuffer
import java.util.UUID
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import org.webrtc.VideoSource
import org.webrtc.VideoTrack

class PlaceholderVideo private constructor(
    private val source: VideoSource,
    private val track: VideoTrack,
) {
    private val thread = HandlerThread("zuno-placeholder-video").apply { start() }
    private val handler = Handler(thread.looper)
    private val tick = object : Runnable {
        override fun run() {
            deliverBlackFrame()
            handler.postDelayed(this, FRAME_INTERVAL_MS)
        }
    }

    private fun start() {
        source.capturerObserver.onCapturerStarted(true)
        handler.post(tick)
    }

    private fun deliverBlackFrame() {
        val buffer = JavaI420Buffer.allocate(WIDTH, HEIGHT)
        fill(buffer.dataY, LUMA_BLACK)
        fill(buffer.dataU, CHROMA_NEUTRAL)
        fill(buffer.dataV, CHROMA_NEUTRAL)
        val frame = VideoFrame(buffer, 0, System.nanoTime())
        source.capturerObserver.onFrameCaptured(frame)
        frame.release()
    }

    private fun release() {
        handler.post {
            handler.removeCallbacks(tick)
            source.capturerObserver.onCapturerStopped()
            track.dispose()
            source.dispose()
            thread.quitSafely()
        }
    }

    companion object {
        private const val WIDTH = 160
        private const val HEIGHT = 120
        private const val FRAME_INTERVAL_MS = 500L
        private const val LUMA_BLACK: Byte = 16
        private const val CHROMA_NEUTRAL: Byte = -128
        private const val UNAVAILABLE = "placeholder video unavailable"
        private val active = mutableMapOf<String, PlaceholderVideo>()

        fun attach(context: Context, engine: FlutterEngine, streamId: String): String? {
            val plugin = engine.plugins.get(FlutterWebRTCPlugin::class.java) as? FlutterWebRTCPlugin
                ?: return unavailable(context, "flutter_webrtc is not registered on this engine")
            val factory = plugin.peerConnectionFactory
                ?: return unavailable(context, "flutter_webrtc has no peer connection factory")
            val stream = plugin.getStreamForId(streamId, "")
                ?: return unavailable(context, "flutter_webrtc has no such stream")
            val registry = runCatching { registry(plugin) }.getOrElse { return unavailable(context, it) }
                ?: return unavailable(context, "flutter_webrtc's track registry is out of reach")
            val source = factory.createVideoSource(false)
            val track = factory.createVideoTrack(UUID.randomUUID().toString(), source)
            registry.putLocalTrack(track.id(), LocalVideoTrack(track))
            stream.addTrack(track)
            val placeholder = PlaceholderVideo(source, track)
            synchronized(active) { active[track.id()] = placeholder }
            placeholder.start()
            return track.id()
        }

        fun release(trackId: String) {
            synchronized(active) { active.remove(trackId) }?.release()
        }

        fun releaseAll() {
            val all = synchronized(active) { active.values.toList().also { active.clear() } }
            all.forEach { it.release() }
        }

        private fun unavailable(context: Context, reason: String): String? =
            unavailable(context, IllegalStateException(reason))

        private fun unavailable(context: Context, cause: Throwable): String? {
            CaughtErrors.record(context, UNAVAILABLE, cause)
            return null
        }

        private fun fill(plane: ByteBuffer, value: Byte) {
            while (plane.hasRemaining()) plane.put(value)
        }

        private fun registry(plugin: FlutterWebRTCPlugin): MethodCallHandlerImpl? {
            val field = FlutterWebRTCPlugin::class.java.getDeclaredField("methodCallHandler")
            field.isAccessible = true
            return field.get(plugin) as? MethodCallHandlerImpl
        }
    }
}
