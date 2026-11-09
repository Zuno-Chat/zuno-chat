package im.zuno.chat.zuno_http

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.ProtocolException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.net.UnknownServiceException
import javax.net.ssl.SSLException
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString

private const val MAX_QUEUED_BYTES = 16L * 1024 * 1024
private const val NORMAL_CLOSURE = 1000

private val sendableCloseCodes = (1000..1003) + (1007..1014) + (3000..4999)

internal fun socketKindOf(error: Throwable): String = when (error) {
    is UnknownServiceException -> "cleartext"
    is UnknownHostException -> "dns"
    is ConnectException, is NoRouteToHostException -> "connect"
    is SocketTimeoutException -> "timedOut"
    is SSLException -> "tls"
    is ProtocolException -> "protocol"
    is IOException -> "connectionLost"
    else -> "protocol"
}

internal fun interface SocketFactory {
    fun open(request: Request, listener: WebSocketListener): WebSocket
}

internal class WebSocketChannel(private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {
    private val sockets = CallTable<SocketCall>()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (sockets.detached) {
            result.error("cancelled", "The engine has detached", null)
            return
        }
        val id = call.argument<Int>("id")!!
        when (call.method) {
            "connect" -> connect(id, call, result)

            "receive" -> sockets[id]?.receive(result) ?: result.success(null)

            "send" -> sockets[id]?.send(call.argument<ByteArray>("bytes")!!, result)
                ?: result.success(false)

            "close" -> {
                sockets[id]?.close()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun connect(id: Int, call: MethodCall, result: Result) {
        val request = try {
            Request.Builder()
                .url(call.argument<String>("url")!!)
                .apply {
                    call.argument<Map<String, String>>("headers")!!.forEach { (name, value) ->
                        header(name, value)
                    }
                }
                .build()
        } catch (error: IllegalArgumentException) {
            result.error("protocol", detailOf(error), null)
            return
        }
        val socket = SocketCall { sockets.remove(id, it) }
        sockets.replace(id, socket)
        socket.connect(request, result) { built, listener ->
            OkHttpHolder.client.newWebSocket(built, listener)
        }
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        sockets.detach()
    }
}

internal class SocketCall(private val onFinished: (SocketCall) -> Unit) :
    WebSocketListener(),
    NativeCall {
    private val lock = Any()
    private var socket: WebSocket? = null
    private var connecting: Result? = null
    private var receiving: Result? = null
    private val frames = ArrayDeque<ByteArray>()
    private var queuedBytes = 0L
    private var opened = false
    private var closed = false
    private var failure: Pair<String, String>? = null
    private var removed = false

    fun connect(request: Request, result: Result, factory: SocketFactory) {
        synchronized(lock) { connecting = result }
        val started = factory.open(request, this)
        val abandoned = synchronized(lock) {
            socket = started
            closed
        }
        if (abandoned) started.cancel()
    }

    fun receive(result: Result) = synchronized(lock) {
        val failed = failure
        when {
            frames.isNotEmpty() -> {
                val frame = frames.removeFirst()
                queuedBytes -= frame.size
                result.success(frame)
            }

            failed != null -> {
                result.error(failed.first, failed.second, null)
                remove()
            }

            closed -> {
                result.success(null)
                remove()
            }

            else -> receiving = result
        }
    }

    fun send(bytes: ByteArray, result: Result) {
        val open = synchronized(lock) { socket.takeIf { !closed && failure == null } }
        result.success(open?.send(bytes.toByteString()) ?: false)
    }

    fun close() {
        val (open, upgraded) = synchronized(lock) {
            closed = true
            receiving?.success(null)
            receiving = null
            remove()
            socket to opened
        }
        if (upgraded) open?.close(NORMAL_CLOSURE, null) else open?.cancel()
    }

    override fun cancel() {
        val open = synchronized(lock) {
            closed = true
            remove()
            socket
        }
        open?.cancel()
    }

    override fun onOpen(webSocket: WebSocket, response: Response) = synchronized(lock) {
        opened = true
        connecting?.success(null)
        connecting = null
    }

    override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
        val overflow = synchronized(lock) {
            val frame = bytes.toByteArray()
            val waiting = receiving
            if (waiting != null) {
                receiving = null
                waiting.success(frame)
                false
            } else {
                frames.addLast(frame)
                queuedBytes += frame.size
                queuedBytes > MAX_QUEUED_BYTES
            }
        }
        if (overflow) {
            webSocket.cancel()
        }
    }

    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        webSocket.close(if (code in sendableCloseCodes) code else NORMAL_CLOSURE, null)
    }

    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = synchronized(lock) {
        closed = true
        if (frames.isEmpty()) {
            receiving?.let {
                receiving = null
                it.success(null)
                remove()
            }
        }
    }

    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        synchronized(lock) {
            val failed = socketKindOf(t) to detailOf(t)
            val waitingConnect = connecting
            connecting = null
            if (waitingConnect != null) {
                if (response != null) {
                    waitingConnect.error("upgrade", "HTTP ${response.code}", response.code)
                } else {
                    waitingConnect.error(failed.first, failed.second, null)
                }
                remove()
                return
            }
            if (closed) return
            failure = failed
            val waiting = receiving ?: return
            receiving = null
            waiting.error(failed.first, failed.second, null)
            remove()
        }
    }

    private fun remove() {
        if (removed) return
        removed = true
        onFinished(this)
    }
}
