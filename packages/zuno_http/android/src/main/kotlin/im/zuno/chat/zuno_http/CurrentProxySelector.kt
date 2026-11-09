package im.zuno.chat.zuno_http

import java.io.IOException
import java.net.Proxy
import java.net.ProxySelector
import java.net.SocketAddress
import java.net.URI

object CurrentProxySelector : ProxySelector() {
    override fun select(uri: URI?): List<Proxy> =
        ProxySelector.getDefault()?.select(uri) ?: listOf(Proxy.NO_PROXY)

    override fun connectFailed(uri: URI?, address: SocketAddress?, failure: IOException?) {
        ProxySelector.getDefault()?.connectFailed(uri, address, failure)
    }
}
