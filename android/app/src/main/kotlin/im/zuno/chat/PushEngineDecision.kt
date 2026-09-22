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

    fun shouldHoldWakeLock(
        appEngineAlive: Boolean,
        hasHeadlessEngine: Boolean,
    ): Boolean = !appEngineAlive && hasHeadlessEngine
}
