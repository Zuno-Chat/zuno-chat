package im.zuno.chat

enum class FcmAvailability(val wire: String) {
    AVAILABLE("available"),
    UPDATE_REQUIRED("updateRequired"),
    DISABLED("disabled"),
    UNAVAILABLE("unavailable"),
    NOT_CONFIGURED("notConfigured"),
    UNKNOWN("unknown"),
}

object FcmAvailabilityDecision {
    const val CHECK_FAILED = -1
    private const val SUCCESS = 0
    private const val SERVICE_MISSING = 1
    private const val SERVICE_VERSION_UPDATE_REQUIRED = 2
    private const val SERVICE_DISABLED = 3
    private const val SERVICE_INVALID = 9
    private const val SERVICE_UPDATING = 18
    private const val SERVICE_MISSING_PERMISSION = 19

    fun decide(firebaseConfigured: Boolean?, playServicesStatus: Int): FcmAvailability =
        when (firebaseConfigured) {
            null -> FcmAvailability.UNKNOWN

            false -> FcmAvailability.NOT_CONFIGURED

            true -> when (playServicesStatus) {
                SUCCESS -> FcmAvailability.AVAILABLE

                SERVICE_VERSION_UPDATE_REQUIRED, SERVICE_UPDATING -> FcmAvailability.UPDATE_REQUIRED

                SERVICE_DISABLED -> FcmAvailability.DISABLED

                SERVICE_MISSING,
                SERVICE_INVALID,
                SERVICE_MISSING_PERMISSION,
                -> FcmAvailability.UNAVAILABLE

                else -> FcmAvailability.UNKNOWN
            }
        }
}
