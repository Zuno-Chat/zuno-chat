package im.zuno.chat.zuno_http

import java.io.EOFException
import java.net.ConnectException
import java.net.ProtocolException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.net.UnknownServiceException
import javax.net.ssl.SSLHandshakeException
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private val upgrade = Request.Builder().url("wss://sfu.example.org/rtc").build()

private fun response(code: Int) = Response.Builder()
    .request(upgrade)
    .protocol(Protocol.HTTP_1_1)
    .code(code)
    .message("")
    .build()

private class FakeSocket : WebSocket {
    var cancelled = false
    var closedWith: Int? = null

    override fun request() = upgrade

    override fun queueSize() = 0L

    override fun send(text: String) = true

    override fun send(bytes: ByteString) = true

    override fun close(code: Int, reason: String?): Boolean {
        closedWith = code
        return true
    }

    override fun cancel() {
        cancelled = true
    }
}

private class SocketHarness {
    val socket = FakeSocket()
    val connecting = Reply()
    var removals = 0
    val call = SocketCall { removals++ }

    fun connect(during: () -> Unit = {}): SocketHarness {
        call.connect(upgrade, connecting) { _, _ ->
            during()
            socket
        }
        return this
    }

    fun open(): SocketHarness {
        call.onOpen(socket, response(101))
        return this
    }

    fun receive(): Reply = Reply().also { call.receive(it) }
}

class SocketCallTest {
    @Test
    fun `a socket closed while it was being created is cancelled once it exists`() {
        val h = SocketHarness()

        h.connect(during = { h.call.close() })

        assertTrue(h.socket.cancelled)
        assertEquals(1, h.removals)
    }

    @Test
    fun `a refused upgrade answers connect with its status and leaves the table`() {
        val h = SocketHarness().connect()

        h.call.onFailure(h.socket, ProtocolException("Expected HTTP 101"), response(401))

        assertEquals(Failure("upgrade", 401), h.connecting.single)
        assertEquals(1, h.removals)
    }

    @Test
    fun `a failure before the upgrade answers connect with its kind`() {
        val h = SocketHarness().connect()

        h.call.onFailure(h.socket, UnknownHostException("sfu.example.org"), null)

        assertEquals(Failure("dns"), h.connecting.single)
        assertEquals(1, h.removals)
    }

    @Test
    fun `frames that arrived before a receive are delivered first, in order`() {
        val h = SocketHarness().connect().open()

        h.call.onMessage(h.socket, byteArrayOf(1).toByteString())
        h.call.onMessage(h.socket, byteArrayOf(2).toByteString())

        assertArrayEquals(byteArrayOf(1), h.receive().single as ByteArray)
        assertArrayEquals(byteArrayOf(2), h.receive().single as ByteArray)
    }

    @Test
    fun `a server close answers a waiting receive with null and leaves the table`() {
        val h = SocketHarness().connect().open()
        val waiting = h.receive()

        h.call.onClosed(h.socket, 1000, "")

        assertNull(waiting.single)
        assertEquals(1, h.removals)
    }

    @Test
    fun `a drop after the upgrade fails the next receive with its kind`() {
        val h = SocketHarness().connect().open()

        h.call.onFailure(h.socket, EOFException(), null)

        assertEquals(Failure("connectionLost"), h.receive().single)
        assertEquals(1, h.removals)
    }

    @Test
    fun `Dart closing an open socket closes it normally`() {
        val h = SocketHarness().connect().open()

        h.call.close()

        assertEquals(1000, h.socket.closedWith)
        assertEquals(1, h.removals)
    }

    @Test
    fun `too many unread bytes cancel the socket`() {
        val h = SocketHarness().connect().open()

        h.call.onMessage(h.socket, ByteArray(16 * 1024 * 1024 + 1).toByteString())

        assertTrue(h.socket.cancelled)
    }

    @Test
    fun `socket errors map to their kind, most specific first`() {
        assertEquals(
            listOf(
                "cleartext",
                "dns",
                "connect",
                "timedOut",
                "tls",
                "protocol",
                "connectionLost",
                "protocol",
            ),
            listOf(
                UnknownServiceException("CLEARTEXT"),
                UnknownHostException("host"),
                ConnectException("refused"),
                SocketTimeoutException("slow"),
                SSLHandshakeException("bad certificate"),
                ProtocolException("bad frame"),
                EOFException(),
                IllegalStateException("odd"),
            ).map(::socketKindOf),
        )
    }
}
