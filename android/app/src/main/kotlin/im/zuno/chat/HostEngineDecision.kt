package im.zuno.chat

enum class HostEngineFate {
    Keep,
    Destroy,
    Default,
}

object HostEngineDecision {
    fun onHostDetached(callActive: Boolean, adopted: Boolean): HostEngineFate = when {
        callActive -> HostEngineFate.Keep
        adopted -> HostEngineFate.Destroy
        else -> HostEngineFate.Default
    }
}
