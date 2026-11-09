package im.zuno.chat.zuno_http

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class ZunoHttpPlugin : FlutterPlugin {
    private var http: HttpChannel? = null
    private var sockets: WebSocketChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        CronetHolder.warmUp(binding.applicationContext)
        val messenger = binding.binaryMessenger
        http = HttpChannel(messenger.backgroundChannel("zuno/http"))
        sockets = WebSocketChannel(messenger.backgroundChannel("zuno/websocket"))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        http?.detach()
        sockets?.detach()
        http = null
        sockets = null
    }

    private fun BinaryMessenger.backgroundChannel(name: String) =
        MethodChannel(this, name, StandardMethodCodec.INSTANCE, makeBackgroundTaskQueue())
}
