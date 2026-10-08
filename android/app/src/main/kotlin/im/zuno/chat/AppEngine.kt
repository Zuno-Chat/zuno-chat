package im.zuno.chat

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object AppEngine {
    @Volatile
    private var current: FlutterEngine? = null

    @Volatile
    var callsChannel: MethodChannel? = null
        private set

    val alive: Boolean get() = current != null

    fun attach(engine: FlutterEngine) {
        if (current !== engine) callsChannel = null
        current = engine
    }

    fun bindCalls(engine: FlutterEngine, channel: MethodChannel) {
        if (current === engine) callsChannel = channel
    }

    fun detach(engine: FlutterEngine) {
        if (current !== engine) return
        current = null
        callsChannel = null
    }
}
