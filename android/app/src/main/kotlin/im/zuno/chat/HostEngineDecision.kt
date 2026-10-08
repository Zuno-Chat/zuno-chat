package im.zuno.chat

enum class HostEngineFate {
    Keep,
    Destroy,
    Default,
}

enum class EngineKeepReason {
    Call,
    LiveLocation,
}

class EngineKeepReasons {
    private val held = mutableSetOf<EngineKeepReason>()

    val any: Boolean get() = held.isNotEmpty()

    fun holds(reason: EngineKeepReason): Boolean = reason in held

    fun hold(reason: EngineKeepReason) {
        held.add(reason)
    }

    fun release(reason: EngineKeepReason) {
        held.remove(reason)
    }
}

object HostEngineDecision {
    fun onHostDetached(keepAlive: Boolean, adopted: Boolean): HostEngineFate = when {
        keepAlive -> HostEngineFate.Keep
        adopted -> HostEngineFate.Destroy
        else -> HostEngineFate.Default
    }
}
