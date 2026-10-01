package im.zuno.chat

import im.zuno.chat.FcmRouteAction.BootHeadless
import im.zuno.chat.FcmRouteAction.DestroyHeadless
import im.zuno.chat.FcmRouteAction.Finish
import im.zuno.chat.FcmRouteAction.RetireHeadless
import im.zuno.chat.FcmRouteAction.Send
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FcmRoutingTest {
    private val routing = FcmRouting(
        appReadyGraceMs = 10_000,
        headlessBootTimeoutMs = 12_000,
        headlessIdleMs = 30_000,
        headlessIdleAloneMs = 600_000,
        maxBootAttempts = 2,
        bootCooldownMs = 300_000,
        maxJobAgeMs = 60_000,
    )

    private fun bootedHeadless(actions: List<FcmRouteAction>): Int =
        (actions.single { it is BootHeadless } as BootHeadless).engineId

    private fun readyApp(now: Long = 0): Int {
        val app = routing.appAttached(now).engineId
        routing.ready(app, now)
        return app
    }

    private fun idleHeadless(): Int {
        val headless = bootedHeadless(routing.submit("p1", 0))
        routing.ready(headless, 900)
        routing.handled("p1", 1_000)
        return headless
    }

    @Test
    fun `a push goes straight to a ready app engine`() {
        val app = readyApp()

        assertEquals(listOf(Send("p1", app)), routing.submit("p1", 20))
    }

    @Test
    fun `with no engine at all a headless engine boots and gets the push once ready`() {
        val boot = routing.submit("p1", 0)
        val headless = bootedHeadless(boot)
        assertEquals(1, boot.size)

        assertEquals(listOf(Send("p1", headless)), routing.ready(headless, 900))
        assertTrue(routing.isReady(headless))
    }

    @Test
    fun `pushes arriving while the headless engine boots wait for it`() {
        val headless = bootedHeadless(routing.submit("p1", 0))

        assertTrue(routing.submit("p2", 100).isEmpty())
        assertEquals(
            listOf(Send("p1", headless), Send("p2", headless)),
            routing.ready(headless, 900),
        )
    }

    @Test
    fun `a push during app start waits for the app instead of a second client`() {
        val app = routing.appAttached(0).engineId

        assertTrue(routing.submit("p1", 500).isEmpty())
        assertEquals(listOf(Send("p1", app)), routing.ready(app, 2_000))
    }

    @Test
    fun `an app that never gets ready hands its pushes to a headless engine after the grace`() {
        routing.appAttached(0)
        routing.submit("p1", 500)

        assertEquals(10_000L, routing.nextTickAt(500))
        assertTrue(routing.tick(9_999).isEmpty())
        val headless = bootedHeadless(routing.tick(10_000))
        assertEquals(listOf(Send("p1", headless)), routing.ready(headless, 11_000))
    }

    @Test
    fun `an expired app grace never makes the timer spin while the headless engine boots`() {
        routing.appAttached(0)
        routing.submit("p1", 500)
        routing.tick(10_000)

        val next = routing.nextTickAt(10_000)
        assertEquals(22_000L, next)
        assertTrue(next!! > 10_000)
    }

    @Test
    fun `with two starting apps the queue waits for the later grace`() {
        routing.appAttached(0)
        routing.appAttached(8_000)
        routing.submit("p1", 9_000)

        assertEquals(18_000L, routing.nextTickAt(9_000))
        assertTrue(routing.tick(10_000).isEmpty())
        assertTrue(routing.tick(18_000).any { it is BootHeadless })
    }

    @Test
    fun `a push waits for a starting app even when a headless engine is ready`() {
        val headless = bootedHeadless(routing.submit("p1", 0))
        val app = routing.appAttached(100).engineId

        assertTrue(routing.ready(headless, 900).isEmpty())
        assertEquals(
            listOf(Send("p1", app), RetireHeadless(headless)),
            routing.ready(app, 2_000),
        )
    }

    @Test
    fun `while an app starts, new pushes wait for it rather than a busy headless engine`() {
        val headless = bootedHeadless(routing.submit("p1", 0))
        routing.ready(headless, 900)
        val app = routing.appAttached(1_000).engineId

        assertTrue(routing.submit("p2", 1_100).isEmpty())
        assertEquals(listOf(Send("p2", app)), routing.ready(app, 3_000))
    }

    @Test
    fun `an app that misses its grace leaves its pushes to the ready headless engine`() {
        val headless = bootedHeadless(routing.submit("p1", 0))
        routing.ready(headless, 900)
        routing.appAttached(1_000)
        routing.submit("p2", 1_100)

        assertEquals(11_000L, routing.nextTickAt(1_100))
        assertEquals(listOf(Send("p2", headless)), routing.tick(11_000))
    }

    @Test
    fun `the app becoming ready takes pushes queued for a booting headless engine`() {
        val headless = bootedHeadless(routing.submit("p1", 0))
        val app = routing.appAttached(100).engineId

        assertEquals(listOf(Send("p1", app)), routing.ready(app, 500))
        assertEquals(listOf(RetireHeadless(headless)), routing.ready(headless, 900))
    }

    @Test
    fun `a handled push releases its service exactly once`() {
        readyApp()
        routing.submit("p1", 0)

        assertEquals(listOf(Finish("p1")), routing.handled("p1", 10))
        assertTrue(routing.handled("p1", 20).isEmpty())
    }

    @Test
    fun `a job is only reported in flight to the engine it was sent to`() {
        val app = readyApp()
        routing.submit("p1", 0)

        assertTrue(routing.isInFlight("p1", app))
        assertFalse(routing.isInFlight("p1", app + 1))
        routing.handled("p1", 10)
        assertFalse(routing.isInFlight("p1", app))
    }

    @Test
    fun `pushes in flight to an app that goes away are sent again to a headless engine`() {
        val app = readyApp()
        routing.submit("p1", 0)
        routing.submit("p2", 5)

        val headless = bootedHeadless(routing.gone(app, 10))
        assertEquals(
            listOf(Send("p1", headless), Send("p2", headless)),
            routing.ready(headless, 900),
        )
    }

    @Test
    fun `a push the app engine cannot take goes to a headless engine at once`() {
        val app = readyApp()
        routing.submit("p1", 0)

        val headless = bootedHeadless(routing.sendFailed("p1", 10))
        assertEquals(listOf(Send("p1", headless)), routing.ready(headless, 900))
        assertEquals(listOf(Send("p2", headless)), routing.submit("p2", 950))

        routing.ready(app, 1_000)
        assertEquals(listOf(Send("p3", app)), routing.submit("p3", 1_100))
    }

    @Test
    fun `a ready headless engine that fails a send is retired and replaced`() {
        val first = bootedHeadless(routing.submit("p1", 0))
        routing.ready(first, 900)

        val actions = routing.sendFailed("p1", 1_000)
        assertTrue(actions.contains(RetireHeadless(first)))
        assertTrue(routing.isBroken(first))
        val second = bootedHeadless(actions)
        assertEquals(listOf(Send("p1", second)), routing.ready(second, 1_900))
    }

    @Test
    fun `a never-ready headless engine is destroyed and replaced, then pushes are let go`() {
        val first = bootedHeadless(routing.submit("p1", 0))
        assertEquals(12_000L, routing.nextTickAt(0))

        val retry = routing.tick(12_000)
        assertTrue(retry.contains(DestroyHeadless(first)))
        val second = bootedHeadless(retry)

        val giveUp = routing.tick(24_000)
        assertTrue(giveUp.contains(DestroyHeadless(second)))
        assertTrue(giveUp.contains(Finish("p1")))
        assertFalse(giveUp.any { it is BootHeadless })
    }

    @Test
    fun `an engine dropped for being slow is told it is not wanted when it finally gets ready`() {
        val first = bootedHeadless(routing.submit("p1", 0))
        val second = bootedHeadless(routing.tick(12_000))

        assertTrue(routing.ready(first, 13_000).isEmpty())
        assertFalse(routing.isReady(first))
        assertEquals(listOf(Send("p1", second)), routing.ready(second, 14_000))
    }

    @Test
    fun `after giving up, no engine is booted until the cool-down passes`() {
        val first = bootedHeadless(routing.submit("p1", 0))
        val second = bootedHeadless(routing.bootFailed(first, 10))
        routing.bootFailed(second, 20)

        assertEquals(listOf(Finish("p2")), routing.submit("p2", 1_000))
        assertTrue(routing.submit("p3", 300_020).any { it is BootHeadless })
    }

    @Test
    fun `a failed boot is retried, then the pushes are let go`() {
        val first = bootedHeadless(routing.submit("p1", 0))

        val second = bootedHeadless(routing.bootFailed(first, 10))
        val giveUp = routing.bootFailed(second, 20)

        assertEquals(listOf(Finish("p1")), giveUp)
    }

    @Test
    fun `boot attempts start over after a good boot`() {
        val first = bootedHeadless(routing.submit("p1", 0))
        val second = bootedHeadless(routing.bootFailed(first, 10))
        routing.ready(second, 900)
        routing.handled("p1", 1_000)
        routing.gone(second, 1_100)

        val third = bootedHeadless(routing.submit("p2", 1_200))
        assertTrue(routing.bootFailed(third, 1_300).any { it is BootHeadless })
    }

    @Test
    fun `an idle headless engine is asked to retire as soon as an app engine attaches`() {
        val headless = idleHeadless()
        val attached = routing.appAttached(2_000)

        assertEquals(listOf(RetireHeadless(headless)), attached.actions)
        assertTrue(routing.ready(attached.engineId, 3_000).isEmpty())
        assertTrue(routing.tick(40_000).isEmpty())
        assertTrue(routing.gone(headless, 40_100).isEmpty())
        assertNull(routing.nextTickAt(40_100))
    }

    @Test
    fun `a headless engine with work in flight is left alone when an app engine attaches`() {
        val headless = bootedHeadless(routing.submit("p1", 0))
        routing.ready(headless, 900)

        assertTrue(routing.appAttached(1_000).actions.isEmpty())
        assertTrue(routing.isReady(headless))
    }

    @Test
    fun `a retiring headless engine that goes quiet is destroyed and forgotten`() {
        val headless = idleHeadless()
        val app = routing.appAttached(2_000).engineId
        routing.ready(app, 3_000)

        assertEquals(listOf(DestroyHeadless(headless)), routing.quiet(headless, 3_100))
        assertFalse(routing.needsHeadless(headless, 3_100))
        assertNull(routing.nextTickAt(3_100))
    }

    @Test
    fun `a retiring headless engine that goes quiet is kept when it is needed after all`() {
        val headless = idleHeadless()
        val app = routing.appAttached(2_000).engineId
        routing.ready(app, 3_000)
        routing.gone(app, 3_010)
        routing.submit("p2", 3_020)

        assertEquals(listOf(Send("p2", headless)), routing.quiet(headless, 3_050))
    }

    @Test
    fun `a quiet answer while an app starts lets the retired headless engine go`() {
        val headless = idleHeadless()
        routing.appAttached(2_000)
        routing.submit("p2", 2_100)

        assertFalse(routing.needsHeadless(headless, 2_100))
        assertEquals(listOf(DestroyHeadless(headless)), routing.quiet(headless, 2_200))
    }

    @Test
    fun `a broken headless engine that goes quiet is destroyed and forgotten`() {
        val first = bootedHeadless(routing.submit("p1", 0))
        routing.ready(first, 900)
        val second = bootedHeadless(routing.sendFailed("p1", 1_000))

        assertTrue(routing.needsHeadless(first, 1_500))
        assertEquals(listOf(DestroyHeadless(first)), routing.quiet(first, 1_500))
        assertFalse(routing.isBroken(first))
        assertEquals(listOf(Send("p1", second)), routing.ready(second, 2_000))
    }

    @Test
    fun `a quiet answer from an engine that was not asked to retire changes nothing`() {
        val headless = bootedHeadless(routing.submit("p1", 0))

        assertTrue(routing.quiet(headless, 100).isEmpty())
        routing.ready(headless, 900)
        assertTrue(routing.quiet(headless, 1_000).isEmpty())
        assertTrue(routing.isReady(headless))
    }

    @Test
    fun `a headless engine still busy when asked to retire is kept and asked again later`() {
        val headless = idleHeadless()
        val app = routing.appAttached(2_000).engineId
        routing.ready(app, 3_000)

        assertTrue(routing.busy(headless, 3_050).isEmpty())
        assertEquals(33_050L, routing.nextTickAt(3_050))
        assertEquals(listOf(RetireHeadless(headless)), routing.tick(33_050))
    }

    @Test
    fun `a retiring headless engine takes no push until it answers`() {
        val headless = idleHeadless()
        val app = routing.appAttached(2_000).engineId
        routing.ready(app, 3_000)
        routing.gone(app, 3_010)

        assertTrue(routing.submit("p2", 3_020).isEmpty())
        assertTrue(routing.needsHeadless(headless, 3_020))
        assertEquals(listOf(Send("p2", headless)), routing.busy(headless, 3_050))
    }

    @Test
    fun `a retiring engine is only needed while work waits and no app is ready`() {
        val headless = idleHeadless()
        val app = routing.appAttached(2_000).engineId
        routing.ready(app, 3_000)

        assertFalse(routing.needsHeadless(headless, 3_000))
        routing.gone(app, 3_010)
        assertFalse(routing.needsHeadless(headless, 3_010))
        routing.submit("p2", 3_020)
        assertTrue(routing.needsHeadless(headless, 3_020))
    }

    @Test
    fun `a push waiting on a retiring engine boots a fresh one once the old one is gone`() {
        val headless = idleHeadless()
        val app = routing.appAttached(2_000).engineId
        routing.ready(app, 3_000)
        routing.gone(app, 3_010)
        routing.submit("p2", 3_020)

        val fresh = bootedHeadless(routing.gone(headless, 3_050))
        assertEquals(listOf(Send("p2", fresh)), routing.ready(fresh, 4_000))
    }

    @Test
    fun `an idle headless engine stays a while when no app is ready, then retires`() {
        val headless = idleHeadless()

        assertEquals(601_000L, routing.nextTickAt(1_000))
        assertTrue(routing.tick(600_999).isEmpty())
        assertEquals(listOf(Send("p2", headless)), routing.submit("p2", 600_999))
        routing.handled("p2", 601_000)
        assertEquals(listOf(RetireHeadless(headless)), routing.tick(1_201_000))
    }

    @Test
    fun `a headless engine with work in flight is not asked to retire`() {
        val headless = bootedHeadless(routing.submit("p1", 0))
        routing.ready(headless, 900)
        readyApp(1_000)

        assertTrue(routing.tick(50_000).none { it is RetireHeadless })
        routing.handled("p1", 50_001)
        assertEquals(listOf(RetireHeadless(headless)), routing.tick(80_001))
    }

    @Test
    fun `a stale push is let go instead of being replayed after its engine went away`() {
        val app = readyApp()
        routing.submit("old", 0)
        routing.submit("new", 59_000)

        val actions = routing.gone(app, 61_000)

        assertTrue(actions.contains(Finish("old")))
        assertFalse(actions.contains(Finish("new")))
        val headless = bootedHeadless(actions)
        assertEquals(listOf(Send("new", headless)), routing.ready(headless, 62_000))
    }

    @Test
    fun `a push stuck in flight for too long is let go and its engine kept`() {
        val app = readyApp()
        routing.submit("p1", 0)

        assertTrue(routing.tick(59_999).isEmpty())
        assertEquals(listOf(Finish("p1")), routing.tick(60_000))
        assertTrue(routing.isReady(app))
        assertTrue(routing.handled("p1", 61_000).isEmpty())
    }

    @Test
    fun `a push that waits too long for any engine is let go`() {
        val patient = FcmRouting(
            appReadyGraceMs = 10_000,
            headlessBootTimeoutMs = 20_000,
            headlessIdleMs = 30_000,
            headlessIdleAloneMs = 600_000,
            maxBootAttempts = 10,
            bootCooldownMs = 300_000,
            maxJobAgeMs = 60_000,
        )
        patient.submit("p1", 0)
        patient.tick(20_000)
        patient.tick(40_000)

        assertTrue(patient.tick(60_000).contains(Finish("p1")))
    }

    @Test
    fun `the newest ready app engine takes pushes when two exist`() {
        val first = readyApp(0)
        val second = routing.appAttached(100).engineId
        routing.ready(second, 200)

        assertEquals(listOf(Send("p1", second)), routing.submit("p1", 300))
        routing.gone(second, 400)
        assertEquals(listOf(Send("p2", first)), routing.submit("p2", 500))
    }

    @Test
    fun `isStarting, isReady and isBroken follow the headless engine`() {
        val headless = bootedHeadless(routing.submit("p1", 0))
        assertTrue(routing.isStarting(headless))
        assertFalse(routing.isReady(headless))

        routing.ready(headless, 900)
        assertTrue(routing.isReady(headless))
        routing.sendFailed("p1", 1_000)
        assertTrue(routing.isBroken(headless))
        assertFalse(routing.isReady(headless))
        assertFalse(routing.isStarting(12_345))
        assertFalse(routing.isBroken(12_345))
    }

    @Test
    fun `events for engines it does not know change nothing`() {
        assertTrue(routing.ready(42, 0).isEmpty())
        assertTrue(routing.gone(42, 0).isEmpty())
        assertTrue(routing.busy(42, 0).isEmpty())
        assertTrue(routing.bootFailed(42, 0).isEmpty())
        assertTrue(routing.handled("nope", 0).isEmpty())
        assertTrue(routing.sendFailed("nope", 0).isEmpty())
        assertTrue(routing.quiet(42, 0).isEmpty())
        assertFalse(routing.needsHeadless(42, 0))
    }
}
