package im.zuno.chat.zuno_http

import org.junit.Assert.assertEquals
import org.junit.Test

class CronetFailureTest {
    @Test
    fun `an unresolved name is a DNS failure`() {
        assertEquals("dns", kindOf(-105, 0))
    }

    @Test
    fun `no internet is offline`() {
        assertEquals("offline", kindOf(-106, 0))
    }

    @Test
    fun `a network change loses the connection`() {
        assertEquals("connectionLost", kindOf(-21, 0))
    }

    @Test
    fun `a QUIC idle timeout loses the connection`() {
        assertEquals("connectionLost", kindOf(-356, 25))
    }

    @Test
    fun `any other QUIC error is a protocol failure`() {
        assertEquals("protocol", kindOf(-356, 1))
    }

    @Test
    fun `a cleartext refusal is a cleartext failure`() {
        assertEquals("cleartext", kindOf(-29, 0))
    }

    @Test
    fun `an untrusted certificate is a TLS failure`() {
        assertEquals("tls", kindOf(-202, 0))
    }

    @Test
    fun `a refused connection is a connect failure`() {
        assertEquals("connect", kindOf(-102, 0))
    }

    @Test
    fun `a timeout is timed out`() {
        assertEquals("timedOut", kindOf(-7, 0))
    }

    @Test
    fun `an unknown code is a protocol failure`() {
        assertEquals("protocol", kindOf(-9999, 0))
    }

    @Test
    fun `a failed HTTP2 ping loses the connection`() {
        assertEquals("connectionLost", kindOf(-352, 0))
    }

    @Test
    fun `a QUIC goaway that can be retried loses the connection`() {
        assertEquals("connectionLost", kindOf(-381, 0))
    }

    @Test
    fun `network access denied in the background is offline`() {
        assertEquals("offline", kindOf(-138, 0))
    }

    @Test
    fun `a bad proxy certificate is a TLS failure`() {
        assertEquals("tls", kindOf(-136, 0))
    }

    @Test
    fun `a failed SOCKS connection is a connect failure`() {
        assertEquals("connect", kindOf(-120, 0))
    }
}
