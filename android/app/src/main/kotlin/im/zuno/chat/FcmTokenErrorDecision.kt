package im.zuno.chat

enum class FcmTokenFailure(val wire: String) {
    NO_PLAY_SERVICES("noPlayServices"),
    NOT_CONFIGURED("notConfigured"),
    UNAVAILABLE("unavailable"),
    FAILED("failed"),
}

object FcmTokenErrorDecision {
    private const val MISSING_SERVICE = "MISSING_INSTANCEID_SERVICE"
    private const val NOT_INITIALIZED = "Default FirebaseApp is not initialized"
    private val retryable = listOf(
        "SERVICE_NOT_AVAILABLE",
        "INTERNAL_SERVER_ERROR",
        "InternalServerError",
        "TIMEOUT",
    )

    fun classify(messages: List<String?>): FcmTokenFailure {
        val text = messages.filterNotNull()
        return when {
            text.any { MISSING_SERVICE in it } -> FcmTokenFailure.NO_PLAY_SERVICES
            text.any { NOT_INITIALIZED in it } -> FcmTokenFailure.NOT_CONFIGURED
            text.any { message -> retryable.any { it in message } } -> FcmTokenFailure.UNAVAILABLE
            else -> FcmTokenFailure.FAILED
        }
    }
}
