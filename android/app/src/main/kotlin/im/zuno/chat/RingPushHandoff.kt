package im.zuno.chat

class RingPushHandoff(private val capacity: Int = CAPACITY) {
    private class Verdict(val outcome: RingPushOutcome, val judgedAtMs: Long)

    private val verdicts = object : LinkedHashMap<String, Verdict>() {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Verdict>?): Boolean =
            size > capacity
    }

    @Synchronized
    fun keep(messageId: String?, outcome: RingPushOutcome, judgedAtMs: Long) {
        if (messageId != null) verdicts[messageId] = Verdict(outcome, judgedAtMs)
    }

    fun takeOrJudge(
        messageId: String?,
        nowMs: Long,
        judge: () -> RingPushOutcome,
    ): RingPushOutcome = take(messageId, nowMs) ?: judge()

    @Synchronized
    private fun take(messageId: String?, nowMs: Long): RingPushOutcome? {
        val verdict = messageId?.let { verdicts.remove(it) } ?: return null
        val ring = verdict.outcome as? RingPushOutcome.Ring ?: return verdict.outcome
        val leftMs = ring.ringMs - (nowMs - verdict.judgedAtMs).coerceAtLeast(0)
        if (leftMs <= 0) return RingPushOutcome.Drop(RingDropReason.STALE)
        return ring.copy(ringMs = leftMs)
    }

    companion object {
        const val CAPACITY = 16
    }
}
