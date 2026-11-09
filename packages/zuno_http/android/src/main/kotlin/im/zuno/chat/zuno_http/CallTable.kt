package im.zuno.chat.zuno_http

import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ConcurrentHashMap

internal interface NativeCall {
    fun cancel()
}

internal class CallTable<T : NativeCall> {
    private val calls = ConcurrentHashMap<Int, T>()

    @Volatile var detached = false
        private set

    operator fun get(id: Int): T? = calls[id]

    fun find(id: Int, result: Result): T? =
        calls[id] ?: null.also { result.error("cancelled", "No call $id", null) }

    fun replace(id: Int, call: T) {
        val stale = synchronized(this) { if (detached) call else calls.put(id, call) }
        stale?.cancel()
    }

    fun remove(id: Int, call: T) {
        calls.remove(id, call)
    }

    fun detach() {
        val all = synchronized(this) {
            detached = true
            calls.values.toList().also { calls.clear() }
        }
        all.forEach { it.cancel() }
    }
}
