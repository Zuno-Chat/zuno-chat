package im.zuno.chat

sealed interface FcmRouteAction {
    data class Send(val jobId: String, val engineId: Int) : FcmRouteAction

    data class BootHeadless(val engineId: Int) : FcmRouteAction

    data class RetireHeadless(val engineId: Int) : FcmRouteAction

    data class DestroyHeadless(val engineId: Int) : FcmRouteAction

    data class Finish(val jobId: String) : FcmRouteAction
}

data class FcmAppAttached(val engineId: Int, val actions: List<FcmRouteAction>)

class FcmRouting(
    private val appReadyGraceMs: Long = APP_READY_GRACE_MS,
    private val headlessBootTimeoutMs: Long = HEADLESS_BOOT_TIMEOUT_MS,
    private val headlessIdleMs: Long = HEADLESS_IDLE_MS,
    private val headlessIdleAloneMs: Long = HEADLESS_IDLE_ALONE_MS,
    private val maxBootAttempts: Int = MAX_BOOT_ATTEMPTS,
    private val bootCooldownMs: Long = BOOT_COOLDOWN_MS,
    private val maxJobAgeMs: Long = MAX_JOB_AGE_MS,
) {
    private enum class Kind { APP, HEADLESS }

    private enum class Stage { STARTING, READY, RETIRING, BROKEN }

    private class Engine(val kind: Kind, var stage: Stage, val since: Long, var lastActive: Long)

    private var nextEngineId = 1
    private var failedBoots = 0
    private var coolDownUntil = Long.MIN_VALUE
    private val engines = LinkedHashMap<Int, Engine>()
    private val queued = LinkedHashSet<String>()
    private val inFlight = LinkedHashMap<String, Int>()
    private val submittedAt = HashMap<String, Long>()

    fun appAttached(now: Long): FcmAppAttached {
        val id = nextEngineId++
        engines[id] = Engine(Kind.APP, Stage.STARTING, now, now)
        return FcmAppAttached(id, retireIdleHeadless())
    }

    fun isStarting(engineId: Int): Boolean = engines[engineId]?.stage == Stage.STARTING

    fun isReady(engineId: Int): Boolean = engines[engineId]?.stage == Stage.READY

    fun isBroken(engineId: Int): Boolean = engines[engineId]?.stage == Stage.BROKEN

    fun isInFlight(jobId: String, engineId: Int): Boolean = inFlight[jobId] == engineId

    fun needsHeadless(engineId: Int, now: Long): Boolean =
        engines[engineId]?.kind == Kind.HEADLESS && queued.isNotEmpty() && !appTakesPushes(now)

    fun ready(engineId: Int, now: Long): List<FcmRouteAction> {
        val engine = engines[engineId] ?: return emptyList()
        if (engine.kind == Kind.HEADLESS) {
            if (engine.stage != Stage.STARTING) return emptyList()
            failedBoots = 0
        }
        engine.stage = Stage.READY
        engine.lastActive = now
        return route(now) + retireUnneededHeadless()
    }

    fun busy(engineId: Int, now: Long): List<FcmRouteAction> {
        val engine = engines[engineId] ?: return emptyList()
        if (engine.stage != Stage.RETIRING) return emptyList()
        engine.stage = Stage.READY
        engine.lastActive = now
        return route(now)
    }

    fun quiet(engineId: Int, now: Long): List<FcmRouteAction> {
        val engine = engines[engineId] ?: return emptyList()
        if (engine.kind != Kind.HEADLESS) return emptyList()
        return when (engine.stage) {
            Stage.RETIRING -> if (needsHeadless(engineId, now)) {
                busy(engineId, now)
            } else {
                destroyed(engineId, now)
            }

            Stage.BROKEN -> destroyed(engineId, now)

            Stage.STARTING, Stage.READY -> emptyList()
        }
    }

    fun gone(engineId: Int, now: Long): List<FcmRouteAction> {
        engines.remove(engineId) ?: return emptyList()
        return requeueFrom(engineId, now) + route(now)
    }

    fun bootFailed(engineId: Int, now: Long): List<FcmRouteAction> {
        val engine = engines[engineId] ?: return emptyList()
        if (engine.kind != Kind.HEADLESS || engine.stage != Stage.STARTING) return emptyList()
        engines.remove(engineId)
        failedBoots++
        return route(now)
    }

    fun submit(jobId: String, now: Long): List<FcmRouteAction> {
        queued += jobId
        submittedAt[jobId] = now
        return route(now)
    }

    fun handled(jobId: String, now: Long): List<FcmRouteAction> {
        val engineId = inFlight.remove(jobId)
        if (engineId == null && !queued.remove(jobId)) return emptyList()
        submittedAt.remove(jobId)
        engineId?.let { engines[it]?.lastActive = now }
        return listOf(FcmRouteAction.Finish(jobId)) + route(now)
    }

    fun sendFailed(jobId: String, now: Long): List<FcmRouteAction> {
        val engineId = inFlight.remove(jobId) ?: return emptyList()
        queued += jobId
        val engine = engines[engineId] ?: return route(now)
        engine.stage = Stage.BROKEN
        if (engine.kind == Kind.APP) return route(now)
        failedBoots++
        return listOf(FcmRouteAction.RetireHeadless(engineId)) +
            requeueFrom(engineId, now) +
            route(now)
    }

    fun tick(now: Long): List<FcmRouteAction> {
        val actions = mutableListOf<FcmRouteAction>()
        actions += dropStale(now)
        for ((id, engine) in engines.entries.toList()) {
            if (engine.kind != Kind.HEADLESS) continue
            if (engine.stage == Stage.STARTING && now - engine.since >= headlessBootTimeoutMs) {
                engines.remove(id)
                failedBoots++
                actions += FcmRouteAction.DestroyHeadless(id)
            } else if (engine.stage == Stage.READY && isIdle(id, engine, now)) {
                engine.stage = Stage.RETIRING
                actions += FcmRouteAction.RetireHeadless(id)
            }
        }
        return actions + route(now)
    }

    fun nextTickAt(now: Long): Long? {
        val deadlines = mutableListOf<Long>()
        submittedAt.values.minOrNull()?.let { deadlines += it + maxJobAgeMs }
        if (queued.isNotEmpty()) {
            engines.values
                .filter { it.kind == Kind.APP && it.stage == Stage.STARTING }
                .map { it.since + appReadyGraceMs }
                .filter { it > now }
                .maxOrNull()
                ?.let { deadlines += it }
        }
        for ((id, engine) in engines) {
            if (engine.kind != Kind.HEADLESS) continue
            when (engine.stage) {
                Stage.STARTING -> deadlines += engine.since + headlessBootTimeoutMs
                Stage.READY -> if (!hasWork(id)) deadlines += engine.lastActive + idleLimit()
                Stage.RETIRING, Stage.BROKEN -> Unit
            }
        }
        return deadlines.minOrNull()
    }

    private fun destroyed(engineId: Int, now: Long): List<FcmRouteAction> =
        listOf(FcmRouteAction.DestroyHeadless(engineId)) + gone(engineId, now)

    private fun dropStale(now: Long): List<FcmRouteAction> {
        val stale = submittedAt.filter { now - it.value >= maxJobAgeMs }.keys.toList()
        stale.forEach {
            queued.remove(it)
            inFlight.remove(it)
            submittedAt.remove(it)
        }
        return stale.map { FcmRouteAction.Finish(it) }
    }

    private fun retireUnneededHeadless(): List<FcmRouteAction> =
        if (readyApp() == null) emptyList() else retireIdleHeadless()

    private fun retireIdleHeadless(): List<FcmRouteAction> = engines.entries
        .filter { (id, engine) ->
            engine.kind == Kind.HEADLESS && engine.stage == Stage.READY && !hasWork(id)
        }
        .map { (id, engine) ->
            engine.stage = Stage.RETIRING
            FcmRouteAction.RetireHeadless(id)
        }

    private fun hasWork(engineId: Int): Boolean = inFlight.values.any { it == engineId }

    private fun idleLimit(): Long = if (readyApp() != null) headlessIdleMs else headlessIdleAloneMs

    private fun isIdle(engineId: Int, engine: Engine, now: Long): Boolean =
        !hasWork(engineId) && now - engine.lastActive >= idleLimit()

    private fun readyApp(): Int? = engines.entries
        .lastOrNull { it.value.kind == Kind.APP && it.value.stage == Stage.READY }
        ?.key

    private fun readyHeadless(): Int? = engines.entries
        .firstOrNull { it.value.kind == Kind.HEADLESS && it.value.stage == Stage.READY }
        ?.key

    private fun headlessPending(): Boolean = engines.values.any {
        it.kind == Kind.HEADLESS && (it.stage == Stage.STARTING || it.stage == Stage.RETIRING)
    }

    private fun appStartingWithinGrace(now: Long): Boolean = engines.values.any {
        it.kind == Kind.APP && it.stage == Stage.STARTING && now - it.since < appReadyGraceMs
    }

    private fun appTakesPushes(now: Long): Boolean =
        readyApp() != null || appStartingWithinGrace(now)

    private fun requeueFrom(engineId: Int, now: Long): List<FcmRouteAction> {
        val orphans = inFlight.filterValues { it == engineId }.keys.toList()
        if (orphans.isEmpty()) return emptyList()
        orphans.forEach { inFlight.remove(it) }
        val (stale, retry) = orphans.partition { now - (submittedAt[it] ?: now) >= maxJobAgeMs }
        stale.forEach { submittedAt.remove(it) }
        val waiting = queued.toList()
        queued.clear()
        queued.addAll(retry)
        queued.addAll(waiting)
        return stale.map { FcmRouteAction.Finish(it) }
    }

    private fun finishQueued(): List<FcmRouteAction> {
        val finished = queued.map { FcmRouteAction.Finish(it) }
        queued.forEach { submittedAt.remove(it) }
        queued.clear()
        return finished
    }

    private fun route(now: Long): List<FcmRouteAction> {
        if (queued.isEmpty()) return emptyList()
        val app = readyApp()
        if (app == null && appStartingWithinGrace(now)) return emptyList()
        val target = app ?: readyHeadless()
        if (target != null) {
            val sends = queued.map { FcmRouteAction.Send(it, target) }
            queued.forEach { inFlight[it] = target }
            queued.clear()
            return sends
        }
        if (headlessPending()) return emptyList()
        if (now < coolDownUntil) return finishQueued()
        if (failedBoots >= maxBootAttempts) {
            failedBoots = 0
            coolDownUntil = now + bootCooldownMs
            return finishQueued()
        }
        val id = nextEngineId++
        engines[id] = Engine(Kind.HEADLESS, Stage.STARTING, now, now)
        return listOf(FcmRouteAction.BootHeadless(id))
    }

    companion object {
        const val APP_READY_GRACE_MS = 10_000L
        const val HEADLESS_BOOT_TIMEOUT_MS = 12_000L
        const val HEADLESS_IDLE_MS = 30_000L
        const val HEADLESS_IDLE_ALONE_MS = 600_000L
        const val MAX_BOOT_ATTEMPTS = 2
        const val BOOT_COOLDOWN_MS = 300_000L
        const val MAX_JOB_AGE_MS = 60_000L
    }
}
