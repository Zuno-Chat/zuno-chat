package im.zuno.chat

enum class PushEngineAction {
    UseExistingAppEngine,
    ReuseHeadlessEngine,
    BootHeadlessEngine,
    ReplaceHeadlessEngine,
}

object PushEngineDecision {
    fun decide(
        appEngineAlive: Boolean,
        headlessEngineGeneration: Int?,
        pluginCount: Int,
    ): PushEngineAction = when {
        appEngineAlive -> PushEngineAction.UseExistingAppEngine
        headlessEngineGeneration == null -> PushEngineAction.BootHeadlessEngine
        headlessEngineGeneration == pluginCount -> PushEngineAction.ReuseHeadlessEngine
        else -> PushEngineAction.ReplaceHeadlessEngine
    }

    fun shouldHoldWakeLock(appEngineAlive: Boolean, hasHeadlessEngine: Boolean): Boolean =
        appEngineAlive || hasHeadlessEngine
}

class PushHolds(private val timeoutMs: Long, private val writeOffMs: Long) {
    private class Hold(val key: String?, val at: Long)

    private val holds = ArrayList<Hold>()

    fun acquire(key: String?, now: Long) {
        writeOff(now)
        holds += Hold(key, now)
    }

    fun release(key: String?, now: Long): Boolean {
        writeOff(now)
        val index = if (key == null) 0 else holds.indexOfFirst { it.key == key }
        if (index in holds.indices) holds.removeAt(index)
        return holds.none { now - it.at < timeoutMs }
    }

    private fun writeOff(now: Long) {
        holds.removeAll { now - it.at >= writeOffMs }
    }
}
