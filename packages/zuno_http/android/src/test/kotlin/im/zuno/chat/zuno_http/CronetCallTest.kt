package im.zuno.chat.zuno_http

import java.io.IOException
import java.nio.ByteBuffer
import org.chromium.net.CallbackException
import org.chromium.net.NetworkException
import org.chromium.net.UploadDataProvider
import org.chromium.net.UploadDataSink
import org.chromium.net.UrlRequest
import org.chromium.net.UrlResponseInfo
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeRequest : UrlRequest() {
    val reads = mutableListOf<ByteBuffer>()
    var waitingOnRead = false
    var cancelled = false
    var status = Status.WAITING_FOR_RESPONSE

    override fun start() {}

    override fun followRedirect() {}

    override fun read(buffer: ByteBuffer) {
        check(waitingOnRead) { "Unexpected read attempt." }
        waitingOnRead = false
        reads += buffer
    }

    override fun cancel() {
        cancelled = true
    }

    override fun isDone() = false

    override fun getStatus(listener: StatusListener) = listener.onStatus(status)
}

private class FakeInfo(private val status: Int = 200) : UrlResponseInfo() {
    override fun getUrlChain() = listOf("https://example.org/a")

    override fun getUrl() = "https://example.org/a"

    override fun getHttpStatusCode() = status

    override fun getHttpStatusText() = "OK"

    override fun getAllHeadersAsList() = emptyList<Map.Entry<String, String>>()

    override fun getAllHeaders() = emptyMap<String, List<String>>()

    override fun wasCached() = false

    override fun getNegotiatedProtocol() = "h2"

    override fun getProxyServer() = ""

    override fun getReceivedByteCount() = 0L
}

private class FakeSink(private val length: Long) : UploadDataSink() {
    val succeeded = mutableListOf<Boolean>()
    var readError: Exception? = null
    var rewound = false
    var rewindError: Exception? = null

    override fun onReadSucceeded(finalChunk: Boolean) {
        require(!(finalChunk && length >= 0)) { "Non-chunked upload can't have last chunk" }
        succeeded += finalChunk
    }

    override fun onReadError(exception: Exception) {
        readError = exception
    }

    override fun onRewindSucceeded() {
        rewound = true
    }

    override fun onRewindError(exception: Exception) {
        rewindError = exception
    }
}

private class NetworkChanged : NetworkException("network changed", null) {
    override fun getErrorCode() = ERROR_NETWORK_CHANGED

    override fun getCronetInternalErrorCode() = -21

    override fun immediatelyRetryable() = false
}

private class UploadFailed :
    CallbackException("Exception received from UploadDataProvider", IOException("ended"))

private class Harness(hasBody: Boolean = false, length: Long? = 4L) {
    val request = FakeRequest()
    val info = FakeInfo()
    lateinit var callback: UrlRequest.Callback
    var upload: UploadDataProvider? = null
    var built = 0
    var removals = 0
    val opening = Reply()
    val call =
        CronetCall(bodyLength = if (hasBody) length else null, hasBody = hasBody) { removals++ }

    fun begin(): Harness {
        call.open(opening)
        call.begin { callback, upload ->
            built++
            this.callback = callback
            this.upload = upload
            request
        }
        return this
    }

    fun sink() = FakeSink(upload!!.length)

    fun answerHead() {
        request.waitingOnRead = true
        callback.onResponseStarted(request, info)
    }

    fun deliver(vararg bytes: Byte) {
        val buffer = request.reads.last()
        buffer.put(bytes)
        request.waitingOnRead = true
        callback.onReadCompleted(request, info, buffer)
    }

    fun status(): Any? = Reply().also { call.status(it) }.single
}

class CronetCallTest {
    @Test
    fun `a successful request answers open and the end, then leaves the table`() {
        val h = Harness().begin()

        h.answerHead()
        h.deliver(1, 2, 3)
        h.callback.onSucceeded(h.request, h.info)

        assertEquals(200, (h.opening.single as Map<*, *>)["status"])
        assertEquals(0, h.removals)
        val read = Reply()
        h.call.read(read)
        val end = read.single as Map<*, *>
        assertArrayEquals(byteArrayOf(1, 2, 3), end["bytes"] as ByteArray)
        assertEquals(true, end["end"])
        assertEquals("h2", end["protocol"])
        assertEquals(1, h.removals)
    }

    @Test
    fun `chunks that arrive before a read reach Dart in one reply`() {
        val h = Harness().begin()
        h.answerHead()

        h.deliver(1)
        h.deliver(2)
        val read = Reply()
        h.call.read(read)

        assertArrayEquals(byteArrayOf(1, 2), read.single as ByteArray)
        assertEquals(0, h.removals)
    }

    @Test
    fun `reading stops at four waiting chunks and starts again when Dart reads`() {
        val h = Harness().begin()
        h.answerHead()

        h.deliver(1)
        h.deliver(2)
        h.deliver(3)
        h.deliver(4)
        assertEquals(4, h.request.reads.size)
        assertTrue(h.request.waitingOnRead)
        val read = Reply()
        h.call.read(read)

        assertArrayEquals(byteArrayOf(1, 2, 3, 4), read.single as ByteArray)
        assertEquals(5, h.request.reads.size)
    }

    @Test
    fun `a failure before the head answers open with its kind and leaves the table`() {
        val h = Harness().begin()

        h.callback.onFailed(h.request, null, NetworkChanged())

        assertEquals(Failure("connectionLost"), h.opening.single)
        assertEquals(1, h.removals)
    }

    @Test
    fun `a failure while Cronet waits for upload bytes answers that read`() {
        val h = Harness(hasBody = true).begin()
        val sink = h.sink()
        h.upload!!.read(sink, ByteBuffer.allocate(4))

        h.callback.onFailed(h.request, null, NetworkChanged())

        assertNotNull(sink.readError)
        assertEquals(1, h.removals)
    }

    @Test
    fun `a cancel during an upload read refuses it and ends as cancelled`() {
        val h = Harness(hasBody = true).begin()
        val sink = h.sink()
        h.upload!!.read(sink, ByteBuffer.allocate(4))

        h.call.cancel()
        h.callback.onFailed(h.request, null, UploadFailed())

        assertNotNull(sink.readError)
        assertTrue(h.request.cancelled)
        assertEquals(Failure("cancelled"), h.opening.single)
        assertEquals(1, h.removals)
    }

    @Test
    fun `a cancel before the head ends as cancelled`() {
        val h = Harness().begin()

        h.call.cancel()
        h.callback.onCanceled(h.request, null)

        assertTrue(h.request.cancelled)
        assertEquals(Failure("cancelled"), h.opening.single)
        assertEquals(1, h.removals)
    }

    @Test
    fun `a cancel before the engine is ready answers open and never builds the request`() {
        val h = Harness()
        h.call.open(h.opening)

        h.call.cancel()
        h.call.begin { _, _ ->
            h.built++
            h.request
        }

        assertEquals(Failure("cancelled"), h.opening.single)
        assertEquals(0, h.built)
        assertEquals(1, h.removals)
    }

    @Test
    fun `a write is answered with the next request for bytes`() {
        val h = Harness(hasBody = true, length = 6L).begin()
        val pull = Reply()
        h.call.pullBody(pull)
        val first = h.sink()
        h.upload!!.read(first, ByteBuffer.allocate(4))
        assertEquals(mapOf("want" to 4), pull.single)

        val write = Reply()
        h.call.write(byteArrayOf(1, 2, 3, 4), last = false, result = write)
        assertEquals(listOf(false), first.succeeded)
        assertTrue(write.answers.isEmpty())
        h.upload!!.read(h.sink(), ByteBuffer.allocate(2))

        assertEquals(mapOf("want" to 2), write.single)
    }

    @Test
    fun `the last chunk of an upload with a known length is not marked final`() {
        val h = Harness(hasBody = true, length = 4L).begin()
        val sink = h.sink()
        h.upload!!.read(sink, ByteBuffer.allocate(4))

        h.call.write(byteArrayOf(1, 2, 3, 4), last = true, result = Reply())

        assertEquals(listOf(false), sink.succeeded)
    }

    @Test
    fun `the last chunk of an upload with no length is marked final`() {
        val h = Harness(hasBody = true, length = null).begin()
        val sink = h.sink()
        h.upload!!.read(sink, ByteBuffer.allocate(4))

        h.call.write(byteArrayOf(1, 2), last = true, result = Reply())

        assertEquals(listOf(true), sink.succeeded)
    }

    @Test
    fun `a rewind is told to Dart, and the next pull accepts it`() {
        val h = Harness(hasBody = true).begin()
        val told = Reply()
        h.call.pullBody(told)
        val sink = h.sink()

        h.upload!!.rewind(sink)
        assertEquals(mapOf("rewind" to true), told.single)
        val accepted = Reply()
        h.call.pullBody(accepted)

        assertTrue(sink.rewound)
        h.upload!!.read(h.sink(), ByteBuffer.allocate(4))
        assertEquals(mapOf("want" to 4), accepted.single)
    }

    @Test
    fun `a pending rewind is refused when Dart cancels`() {
        val h = Harness(hasBody = true).begin()
        val sink = h.sink()
        h.upload!!.rewind(sink)

        h.call.cancel()

        assertNotNull(sink.rewindError)
    }

    @Test
    fun `a request that cannot be built answers open and leaves the table`() {
        val h = Harness()
        h.call.open(h.opening)

        h.call.begin { _, _ -> throw IllegalArgumentException("bad header") }

        assertEquals(Failure("protocol"), h.opening.single)
        assertEquals(1, h.removals)
    }

    @Test
    fun `cancelling a finished request nobody read leaves the table`() {
        val h = Harness().begin()
        h.answerHead()
        h.callback.onSucceeded(h.request, h.info)

        h.call.cancel()

        assertEquals(1, h.removals)
    }

    @Test
    fun `a redirect answers open with the 3xx and reads as an empty end`() {
        val h = Harness().begin()

        h.callback.onRedirectReceived(h.request, FakeInfo(status = 302), "https://example.org/b")
        h.callback.onCanceled(h.request, h.info)
        val read = Reply()
        h.call.read(read)

        assertEquals(302, (h.opening.single as Map<*, *>)["status"])
        assertTrue(h.request.cancelled)
        assertEquals(true, (read.single as Map<*, *>)["end"])
        assertEquals(1, h.removals)
    }

    @Test
    fun `a request not yet started is connecting`() {
        val h = Harness()
        h.call.open(h.opening)

        assertEquals("connecting", h.status())
    }

    @Test
    fun `a request on its handshake is connecting`() {
        val h = Harness().begin()
        h.request.status = UrlRequest.Status.SSL_HANDSHAKE

        assertEquals("connecting", h.status())
    }

    @Test
    fun `a request waiting for a free socket is waiting, not connecting`() {
        val h = Harness().begin()
        h.request.status = UrlRequest.Status.WAITING_FOR_AVAILABLE_SOCKET

        assertEquals("waiting", h.status())
    }
}
