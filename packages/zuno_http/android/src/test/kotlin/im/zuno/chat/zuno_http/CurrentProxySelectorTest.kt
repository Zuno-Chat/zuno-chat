package im.zuno.chat.zuno_http

import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.SocketAddress
import java.net.URI
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

class CurrentProxySelectorTest {
    private val original = ProxySelector.getDefault()

    @After
    fun restore() = ProxySelector.setDefault(original)

    private fun fixed(port: Int) = object : ProxySelector() {
        override fun select(uri: URI?): List<Proxy> =
            listOf(Proxy(Proxy.Type.HTTP, InetSocketAddress.createUnresolved("proxy", port)))

        override fun connectFailed(uri: URI?, sa: SocketAddress?, ioe: IOException?) {}
    }

    @Test
    fun `follows the system proxy as it changes`() {
        val uri = URI("https://sfu.example.org/rtc")
        ProxySelector.setDefault(fixed(3128))
        assertEquals(
            3128,
            (CurrentProxySelector.select(uri).single().address() as InetSocketAddress).port,
        )

        ProxySelector.setDefault(fixed(8080))

        assertEquals(
            8080,
            (CurrentProxySelector.select(uri).single().address() as InetSocketAddress).port,
        )
    }

    @Test
    fun `goes direct when there is no system selector`() {
        ProxySelector.setDefault(null)

        assertEquals(
            listOf(Proxy.NO_PROXY),
            CurrentProxySelector.select(URI("https://sfu.example.org/rtc")),
        )
    }
}
