package im.zuno.chat.zuno_notifications

import java.util.UUID

enum class ClientLeaseKind {
    APP,
    BACKGROUND,
    ;

    companion object {
        fun fromWire(wire: String?): ClientLeaseKind? = when (wire) {
            "app" -> APP
            "background" -> BACKGROUND
            else -> null
        }
    }
}

sealed interface ClientLeaseAction {
    data class Grant(val request: Long, val token: String, val forced: Boolean = false) :
        ClientLeaseAction

    data class Deny(val request: Long) : ClientLeaseAction

    data class Yield(val engine: Long) : ClientLeaseAction
}

class ClientLeaseBook {
    private class Lease(val engine: Long, val kind: ClientLeaseKind) {
        var askedToYield = false
    }

    private class Waiter(val request: Long, val engine: Long, val kind: ClientLeaseKind)

    private val leases = LinkedHashMap<String, Lease>()
    private val waiters = ArrayList<Waiter>()

    fun isWaiting(request: Long): Boolean = waiters.any { it.request == request }

    fun acquire(request: Long, engine: Long, kind: ClientLeaseKind): List<ClientLeaseAction> {
        if (leases.isEmpty() || holds(engine)) {
            val granted = grant(request, engine, kind)
            if (kind == ClientLeaseKind.BACKGROUND) return listOf(granted)
            return listOf(granted) + refuseBackgroundWaiters()
        }
        if (kind == ClientLeaseKind.BACKGROUND && appHeld()) {
            return listOf(ClientLeaseAction.Deny(request))
        }
        enqueue(Waiter(request, engine, kind))
        return askToYield()
    }

    fun release(token: String): List<ClientLeaseAction> {
        leases.remove(token) ?: return emptyList()
        return drain()
    }

    fun timedOut(request: Long): List<ClientLeaseAction> {
        val waiter = waiters.firstOrNull { it.request == request } ?: return emptyList()
        waiters.remove(waiter)
        if (waiter.kind == ClientLeaseKind.BACKGROUND) {
            return listOf(ClientLeaseAction.Deny(request))
        }
        return listOf(grant(request, waiter.engine, waiter.kind, forced = true)) +
            refuseBackgroundWaiters()
    }

    fun detached(engine: Long): List<ClientLeaseAction> {
        val tokens = leases.filterValues { it.engine == engine }.keys
        val waiting = waiters.filter { it.engine == engine }
        if (tokens.isEmpty() && waiting.isEmpty()) return emptyList()
        tokens.forEach { leases.remove(it) }
        waiters.removeAll(waiting.toSet())
        return waiting.map { ClientLeaseAction.Deny(it.request) } + drain()
    }

    private fun holds(engine: Long): Boolean = leases.values.any { it.engine == engine }

    private fun appHeld(): Boolean = leases.values.any { it.kind == ClientLeaseKind.APP }

    private fun enqueue(waiter: Waiter) {
        val firstBackground = waiters.indexOfFirst { it.kind == ClientLeaseKind.BACKGROUND }
        if (waiter.kind == ClientLeaseKind.APP && firstBackground >= 0) {
            waiters.add(firstBackground, waiter)
        } else {
            waiters.add(waiter)
        }
    }

    private fun grant(
        request: Long,
        engine: Long,
        kind: ClientLeaseKind,
        forced: Boolean = false,
    ): ClientLeaseAction.Grant {
        val token = UUID.randomUUID().toString()
        leases[token] = Lease(engine, kind)
        return ClientLeaseAction.Grant(request, token, forced)
    }

    private fun drain(): List<ClientLeaseAction> {
        val actions = mutableListOf<ClientLeaseAction>()
        while (waiters.isNotEmpty()) {
            val next = waiters.first()
            when {
                leases.isEmpty() || holds(next.engine) -> {
                    waiters.removeAt(0)
                    actions += grant(next.request, next.engine, next.kind)
                    if (next.kind == ClientLeaseKind.APP) actions += refuseBackgroundWaiters()
                }

                next.kind == ClientLeaseKind.BACKGROUND && appHeld() -> {
                    waiters.removeAt(0)
                    actions += ClientLeaseAction.Deny(next.request)
                }

                else -> break
            }
        }
        return actions + askToYield()
    }

    private fun refuseBackgroundWaiters(): List<ClientLeaseAction> {
        val refused = waiters.filter { it.kind == ClientLeaseKind.BACKGROUND }
        waiters.removeAll(refused.toSet())
        return refused.map { ClientLeaseAction.Deny(it.request) }
    }

    private fun askToYield(): List<ClientLeaseAction> {
        if (waiters.isEmpty()) return emptyList()
        return leases.values
            .filter { lease ->
                lease.kind == ClientLeaseKind.BACKGROUND &&
                    !lease.askedToYield &&
                    waiters.any { it.engine != lease.engine }
            }
            .onEach { it.askedToYield = true }
            .map { it.engine }
            .distinct()
            .map { ClientLeaseAction.Yield(it) }
    }
}
