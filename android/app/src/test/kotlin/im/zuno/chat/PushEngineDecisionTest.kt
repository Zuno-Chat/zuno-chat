package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PushEngineDecisionTest {
    @Test
    fun `boots an engine when the app engine is gone and we own none, a cold process included`() {
        for (pluginCount in listOf(3, 0)) {
            assertEquals(
                "plugins $pluginCount",
                PushEngineAction.BootHeadlessEngine,
                PushEngineDecision.decide(
                    appEngineAlive = false,
                    headlessEngineGeneration = null,
                    pluginCount = pluginCount,
                ),
            )
        }
    }

    @Test
    fun `leaves the app engine alone while it is alive, even when a headless engine exists`() {
        for (generation in listOf(null, 1)) {
            assertEquals(
                "headless $generation",
                PushEngineAction.UseExistingAppEngine,
                PushEngineDecision.decide(
                    appEngineAlive = true,
                    headlessEngineGeneration = generation,
                    pluginCount = 2,
                ),
            )
        }
    }

    @Test
    fun `reuses a headless engine whose plugin is still the newest`() {
        assertEquals(
            PushEngineAction.ReuseHeadlessEngine,
            PushEngineDecision.decide(
                appEngineAlive = false,
                headlessEngineGeneration = 2,
                pluginCount = 2,
            ),
        )
    }

    @Test
    fun `replaces a headless engine that a newer plugin has superseded`() {
        assertEquals(
            PushEngineAction.ReplaceHeadlessEngine,
            PushEngineDecision.decide(
                appEngineAlive = false,
                headlessEngineGeneration = 2,
                pluginCount = 3,
            ),
        )
    }

    @Test
    fun `holds a wakelock for a delivery into our own headless engine`() {
        assertTrue(
            PushEngineDecision.shouldHoldWakeLock(appEngineAlive = false, hasHeadlessEngine = true),
        )
    }

    @Test
    fun `holds a wakelock for every delivery into the app engine, so each release has a hold`() {
        assertTrue(
            PushEngineDecision.shouldHoldWakeLock(appEngineAlive = true, hasHeadlessEngine = false),
        )
    }

    @Test
    fun `takes no wakelock when no engine of ours exists to release it`() {
        assertFalse(
            PushEngineDecision.shouldHoldWakeLock(
                appEngineAlive = false,
                hasHeadlessEngine = false,
            ),
        )
    }
}
