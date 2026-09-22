package im.zuno.chat

enum class CallHangUpAction {
    DeliverToDart,
    StopService,
    Ignore,
}

object CallHangUpDecision {
    fun decide(action: String?, appEngineAlive: Boolean): CallHangUpAction = when {
        action != CallActionReceiver.ACTION_HANG_UP -> CallHangUpAction.Ignore
        appEngineAlive -> CallHangUpAction.DeliverToDart
        else -> CallHangUpAction.StopService
    }

    fun onHostDestroyed(callActive: Boolean, hangUpRequested: Boolean): Boolean =
        callActive && !hangUpRequested
}
