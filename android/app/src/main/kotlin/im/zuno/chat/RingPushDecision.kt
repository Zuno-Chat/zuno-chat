package im.zuno.chat

import im.zuno.chat.zuno_notifications.RingDecisions

enum class RingDropReason {
    STALE,
    FORGED,
}

sealed interface RingPushOutcome {
    data class Ring(val ring: PushedRing, val ringMs: Long) : RingPushOutcome

    data class End(val end: PushedRingEnd) : RingPushOutcome

    data class Drop(val reason: RingDropReason) : RingPushOutcome

    data object ReRegister : RingPushOutcome
}

object RingPushDecision {
    const val DEVICE_TOLERANCE_MS = 60_000L
    private const val RING_GRACE_MS = 5_000L
    private const val MIN_RING_MS = 5_000L

    fun decide(blob: RingBlobOpen, nowMs: Long, serverOffsetMs: Long?): RingPushOutcome =
        when (blob) {
            is RingBlobOpen.Forged -> RingPushOutcome.Drop(RingDropReason.FORGED)

            RingBlobOpen.UnknownVersion -> RingPushOutcome.ReRegister

            is RingBlobOpen.UnknownKid ->
                if (isStale(blob.header.expiry, nowMs, serverOffsetMs, Long.MIN_VALUE)) {
                    RingPushOutcome.Drop(RingDropReason.STALE)
                } else {
                    RingPushOutcome.ReRegister
                }

            is RingBlobOpen.Ended -> RingPushOutcome.End(blob.end)

            is RingBlobOpen.Opened ->
                if (isStale(blob.header.expiry, nowMs, serverOffsetMs, blob.ring.ts)) {
                    RingPushOutcome.Drop(RingDropReason.STALE)
                } else {
                    RingPushOutcome.Ring(
                        blob.ring,
                        ringMs(blob.header.expiry, nowMs, serverOffsetMs, blob.ring.ts),
                    )
                }
        }

    private fun isStale(
        expirySeconds: Long,
        deviceMs: Long,
        serverOffsetMs: Long?,
        atLeastMs: Long,
    ): Boolean {
        val expiryMs = expirySeconds * 1000
        if (serverOffsetMs == null) {
            return maxOf(deviceMs, atLeastMs) > expiryMs + DEVICE_TOLERANCE_MS
        }
        return maxOf(deviceMs + serverOffsetMs, atLeastMs) > expiryMs
    }

    private fun ringMs(
        expirySeconds: Long,
        deviceMs: Long,
        serverOffsetMs: Long?,
        atLeastMs: Long,
    ): Long {
        val nowMs = maxOf(deviceMs + (serverOffsetMs ?: 0L), atLeastMs)
        val remainingMs = expirySeconds * 1000 - nowMs + RING_GRACE_MS
        return remainingMs.coerceIn(MIN_RING_MS, RingDecisions.RING_TIMEOUT_MS)
    }
}
