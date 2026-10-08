package im.zuno.chat

enum class LiveLocationMode(val wire: String) {
    Coarse("coarse"),
    Precise("precise"),
    ;

    companion object {
        fun from(wire: String?): LiveLocationMode? = entries.firstOrNull { it.wire == wire }
    }
}

data class LiveLocationRequest(
    val highAccuracy: Boolean,
    val intervalMs: Long,
    val minDistanceMeters: Float,
)

object LiveLocationRequestDecision {
    private const val FUSED = "fused"
    private const val GPS = "gps"
    private const val NETWORK = "network"
    private const val FUSED_PROVIDER_SDK = 31
    private const val END_GRACE_MS = 120_000L

    fun requestFor(mode: LiveLocationMode): LiveLocationRequest = when (mode) {
        LiveLocationMode.Coarse -> LiveLocationRequest(
            highAccuracy = false,
            intervalMs = 300_000,
            minDistanceMeters = 0f,
        )

        LiveLocationMode.Precise -> LiveLocationRequest(
            highAccuracy = true,
            intervalMs = 5_000,
            minDistanceMeters = 0f,
        )
    }

    fun providerFor(mode: LiveLocationMode, enabled: Set<String>, sdkInt: Int): String? = when {
        sdkInt >= FUSED_PROVIDER_SDK && FUSED in enabled -> FUSED
        mode == LiveLocationMode.Precise && GPS in enabled -> GPS
        NETWORK in enabled -> NETWORK
        GPS in enabled -> GPS
        else -> null
    }

    fun releasesWakeLock(handled: Int, newest: Int): Boolean = handled == newest

    fun isPastEnd(nowMs: Long, endsAtMs: Long): Boolean = nowMs > endsAtMs + END_GRACE_MS
}
