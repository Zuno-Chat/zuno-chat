package im.zuno.chat

enum class ServiceActionRoute {
    DeliverToDart,
    StopService,
    Ignore,
}

object ServiceActionDecision {
    fun route(action: String?, expected: String, dartAttached: Boolean): ServiceActionRoute = when {
        action != expected -> ServiceActionRoute.Ignore
        dartAttached -> ServiceActionRoute.DeliverToDart
        else -> ServiceActionRoute.StopService
    }
}
