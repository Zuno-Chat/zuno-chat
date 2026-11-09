package im.zuno.chat.zuno_http

import io.flutter.plugin.common.MethodChannel.Result
import java.io.IOException
import java.nio.Buffer
import java.nio.ByteBuffer
import org.chromium.net.CronetException
import org.chromium.net.UploadDataProvider
import org.chromium.net.UploadDataSink
import org.chromium.net.UrlRequest
import org.chromium.net.UrlResponseInfo

private const val CHUNK_SIZE = 64 * 1024
private const val MAX_BUFFERED_CHUNKS = 4

private val connectingStatuses = setOf(
    UrlRequest.Status.DOWNLOADING_PAC_FILE,
    UrlRequest.Status.RESOLVING_PROXY_FOR_URL,
    UrlRequest.Status.RESOLVING_HOST_IN_PAC_FILE,
    UrlRequest.Status.ESTABLISHING_PROXY_TUNNEL,
    UrlRequest.Status.RESOLVING_HOST,
    UrlRequest.Status.CONNECTING,
    UrlRequest.Status.SSL_HANDSHAKE,
)

private val bodyDone = mapOf("done" to true)
private val rewindAsked = mapOf("rewind" to true)

internal fun interface RequestFactory {
    fun build(callback: UrlRequest.Callback, upload: UploadDataProvider?): UrlRequest
}

internal class CronetCall(
    private val bodyLength: Long?,
    private val hasBody: Boolean,
    private val onFinished: (CronetCall) -> Unit,
) : NativeCall {
    private val lock = Any()
    private var request: UrlRequest? = null
    private var opening: Result? = null
    private var reading: Result? = null
    private var pulling: Result? = null
    private val chunks = ArrayDeque<ByteArray>()
    private val readBuffer: ByteBuffer by lazy { ByteBuffer.allocateDirect(CHUNK_SIZE) }
    private var cronetReading = false
    private var answered = false
    private var redirected = false
    private var finished = false
    private var cancelled = false
    private var removed = false
    private var protocol: String? = null
    private var failure: Pair<String, String>? = null
    private var uploadRead: Pair<UploadDataSink, ByteBuffer>? = null
    private var rewindSink: UploadDataSink? = null
    private var rewindTold = false

    fun open(result: Result) = synchronized(lock) { opening = result }

    fun begin(factory: RequestFactory) = synchronized(lock) {
        if (cancelled || finished) {
            end("cancelled" to "Cancelled before it started")
            return@synchronized
        }
        try {
            request = factory.build(callback, if (hasBody) upload else null).also { it.start() }
        } catch (error: Throwable) {
            request = null
            end("protocol" to detailOf(error))
        }
    }

    fun failToStart(detail: String) = synchronized(lock) {
        end("engineUnavailable" to detail)
    }

    fun read(result: Result) = synchronized(lock) {
        if (chunks.isEmpty() && !finished) {
            reading = result
            readMore()
        } else {
            deliver(result)
        }
    }

    fun pullBody(result: Result) = synchronized(lock) { answerPull(result) }

    fun write(chunk: ByteArray, last: Boolean, result: Result) = synchronized(lock) {
        val (sink, buffer) = uploadRead ?: (null to null)
        if (sink == null || buffer == null || chunk.size > buffer.remaining()) {
            result.error("protocol", "A body chunk arrived that was not asked for", null)
            return@synchronized
        }
        buffer.put(chunk)
        uploadRead = null
        sink.onReadSucceeded(last && bodyLength == null)
        answerPull(result)
    }

    fun status(result: Result) {
        val (started, ended) = synchronized(lock) { request to finished }
        when {
            ended -> result.success("waiting")

            started == null -> result.success("connecting")

            else -> started.getStatus(object : UrlRequest.StatusListener() {
                override fun onStatus(status: Int) {
                    result.success(if (status in connectingStatuses) "connecting" else "waiting")
                }
            })
        }
    }

    override fun cancel() = synchronized(lock) {
        if (cancelled) return@synchronized
        cancelled = true
        val started = request
        when {
            finished -> remove()

            started == null -> end("cancelled" to "Cancelled before it started")

            else -> {
                releaseUpload()
                started.cancel()
            }
        }
    }

    private val callback = object : UrlRequest.Callback() {
        override fun onRedirectReceived(
            request: UrlRequest,
            info: UrlResponseInfo,
            newLocationUrl: String,
        ) {
            synchronized(lock) {
                redirected = true
                deliverHead(info)
            }
            request.cancel()
        }

        override fun onResponseStarted(request: UrlRequest, info: UrlResponseInfo) =
            synchronized(lock) {
                deliverHead(info)
                readMore()
            }

        override fun onReadCompleted(
            request: UrlRequest,
            info: UrlResponseInfo,
            byteBuffer: ByteBuffer,
        ) = synchronized(lock) {
            cronetReading = false
            (byteBuffer as Buffer).flip()
            chunks.addLast(ByteArray(byteBuffer.remaining()).also { byteBuffer.get(it) })
            val waiting = reading
            reading = null
            if (waiting != null) deliver(waiting) else readMore()
        }

        override fun onSucceeded(request: UrlRequest, info: UrlResponseInfo) = synchronized(lock) {
            protocol = info.negotiatedProtocol
            end(null)
        }

        override fun onFailed(request: UrlRequest, info: UrlResponseInfo?, error: CronetException) =
            synchronized(lock) {
                end(if (cancelled) "cancelled" to "Cancelled" else kindOf(error) to detailOf(error))
            }

        override fun onCanceled(request: UrlRequest, info: UrlResponseInfo?) = synchronized(lock) {
            if (redirected && !cancelled) {
                protocol = info?.negotiatedProtocol
                end(null)
            } else {
                end("cancelled" to "Cancelled")
            }
        }
    }

    private val upload = object : UploadDataProvider() {
        override fun getLength(): Long = bodyLength ?: -1L

        override fun read(uploadDataSink: UploadDataSink, byteBuffer: ByteBuffer) =
            synchronized(lock) {
                if (cancelled || finished) {
                    uploadDataSink.onReadError(IOException("The request has ended"))
                    return@synchronized
                }
                uploadRead = uploadDataSink to byteBuffer
                takePull()?.success(mapOf("want" to byteBuffer.remaining()))
            }

        override fun rewind(uploadDataSink: UploadDataSink) = synchronized(lock) {
            if (cancelled || finished) {
                uploadDataSink.onRewindError(IOException("The request has ended"))
                return@synchronized
            }
            rewindSink = uploadDataSink
            rewindTold = false
            val waiting = takePull() ?: return@synchronized
            rewindTold = true
            waiting.success(rewindAsked)
        }
    }

    private fun answerPull(result: Result) {
        val rewind = rewindSink
        val read = uploadRead
        when {
            failure != null || cancelled -> result.error("cancelled", "The request has ended", null)

            finished -> result.success(bodyDone)

            rewind != null && !rewindTold -> {
                rewindTold = true
                result.success(rewindAsked)
            }

            rewind != null -> {
                rewindTold = false
                rewindSink = null
                pulling = result
                rewind.onRewindSucceeded()
            }

            read != null -> result.success(mapOf("want" to read.second.remaining()))

            else -> pulling = result
        }
    }

    private fun takePull(): Result? = pulling.also { pulling = null }

    private fun deliverHead(info: UrlResponseInfo) {
        if (answered) return
        answered = true
        val waiting = opening ?: return
        opening = null
        waiting.success(
            mapOf(
                "status" to info.httpStatusCode,
                "reason" to info.httpStatusText,
                "headers" to info.allHeaders,
            ),
        )
    }

    private fun deliver(result: Result) {
        val failed = failure
        if (chunks.isEmpty() && failed != null) {
            result.error(failed.first, failed.second, null)
            remove()
            return
        }
        val bytes = drainChunks()
        if (finished && failed == null) {
            result.success(mapOf("bytes" to bytes, "end" to true, "protocol" to protocol))
            remove()
        } else {
            result.success(bytes)
            readMore()
        }
    }

    private fun drainChunks(): ByteArray? {
        if (chunks.size <= 1) return chunks.removeFirstOrNull()
        val joined = ByteArray(chunks.sumOf { it.size })
        var offset = 0
        while (chunks.isNotEmpty()) {
            val chunk = chunks.removeFirst()
            chunk.copyInto(joined, offset)
            offset += chunk.size
        }
        return joined
    }

    private fun readMore() {
        val started = request ?: return
        if (finished || cronetReading || !answered || redirected) return
        if (chunks.size >= MAX_BUFFERED_CHUNKS) return
        cronetReading = true
        (readBuffer as Buffer).clear()
        started.read(readBuffer)
    }

    private fun end(reason: Pair<String, String>?) {
        if (finished) return
        finished = true
        failure = reason
        releaseUpload()
        answerAll()
        if (cancelled || !answered) remove()
    }

    private fun releaseUpload() {
        val sink = uploadRead?.first
        val rewind = rewindSink
        uploadRead = null
        rewindSink = null
        sink?.onReadError(IOException("The request has ended"))
        rewind?.onRewindError(IOException("The request has ended"))
    }

    private fun answerAll() {
        val failed = failure
        takePull()?.let {
            if (failed !=
                null
            ) {
                it.error("cancelled", failed.second, null)
            } else {
                it.success(bodyDone)
            }
        }
        val waitingOpen = opening
        opening = null
        when {
            waitingOpen == null -> Unit
            failed != null -> waitingOpen.error(failed.first, failed.second, null)
            else -> waitingOpen.error("protocol", "The request ended without a response", null)
        }
        val waitingRead = reading
        reading = null
        if (waitingRead != null) deliver(waitingRead)
    }

    private fun remove() {
        if (removed) return
        removed = true
        onFinished(this)
    }
}
