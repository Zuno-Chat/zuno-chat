package im.zuno.chat

enum class PlayServicesAvailability {
    AVAILABLE,
    UPDATE_REQUIRED,
    UNAVAILABLE,
}

object PlayServicesDecision {
    private const val SUCCESS = 0
    private const val SERVICE_VERSION_UPDATE_REQUIRED = 2
    private const val SERVICE_UPDATING = 18

    fun decide(statusCode: Int): PlayServicesAvailability = when (statusCode) {
        SUCCESS -> PlayServicesAvailability.AVAILABLE
        SERVICE_VERSION_UPDATE_REQUIRED,
        SERVICE_UPDATING,
        -> PlayServicesAvailability.UPDATE_REQUIRED
        else -> PlayServicesAvailability.UNAVAILABLE
    }
}
