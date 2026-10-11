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
        appEngineGeneration: Int,
    ): PushEngineAction = when {
        appEngineAlive -> PushEngineAction.UseExistingAppEngine
        headlessEngineGeneration == null -> PushEngineAction.BootHeadlessEngine
        headlessEngineGeneration == appEngineGeneration -> PushEngineAction.ReuseHeadlessEngine
        else -> PushEngineAction.ReplaceHeadlessEngine
    }
}
