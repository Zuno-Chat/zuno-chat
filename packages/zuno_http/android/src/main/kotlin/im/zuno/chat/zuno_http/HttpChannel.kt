package im.zuno.chat.zuno_http

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors

internal class HttpChannel(private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val calls = CallTable<CronetCall>()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (calls.detached) {
            result.error("cancelled", "The engine has detached", null)
            return
        }
        when (call.method) {
            "ready" -> CronetHolder.engine.whenComplete { _, error ->
                if (error ==
                    null
                ) {
                    result.success(null)
                } else {
                    result.error("engineUnavailable", detailOf(error), null)
                }
            }

            "open" -> open(call, result)

            "pullBody" -> calls.find(call.id, result)?.pullBody(result)

            "write" -> calls.find(call.id, result)?.write(
                call.argument<ByteArray>("chunk")!!,
                call.argument<Boolean>("last")!!,
                result,
            )

            "read" -> calls.find(call.id, result)?.read(result)

            "status" -> calls.find(call.id, result)?.status(result)

            "cancel" -> {
                calls[call.id]?.cancel()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        calls.detach()
    }

    private fun open(call: MethodCall, result: Result) {
        val id = call.id
        val method = call.argument<String>("method")!!
        val url = call.argument<String>("url")!!
        val headers = call.argument<Map<String, String>>("headers")!!
        val request = CronetCall(
            bodyLength = call.argument<Number>("bodyLength")?.toLong(),
            hasBody = call.argument<Boolean>("hasBody")!!,
            onFinished = { calls.remove(id, it) },
        )
        request.open(result)
        calls.replace(id, request)
        CronetHolder.engine.whenComplete { engine, error ->
            if (error != null) {
                request.failToStart(detailOf(error))
                return@whenComplete
            }
            request.begin { callback, upload ->
                engine.newUrlRequestBuilder(url, callback, callbacks)
                    .setHttpMethod(method)
                    .apply {
                        headers.forEach { (name, value) -> addHeader(name, value) }
                        if (upload != null) setUploadDataProvider(upload, callbacks)
                    }
                    .build()
            }
        }
    }

    private val MethodCall.id: Int get() = argument<Int>("id")!!

    private companion object {
        const val CALLBACK_THREADS = 4

        val callbacks = Executors.newFixedThreadPool(CALLBACK_THREADS) { runnable ->
            Thread(runnable, "zuno-http").apply { isDaemon = true }
        }
    }
}
