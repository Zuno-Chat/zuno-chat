package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class PushEngineDecisionTest {
    @Test
    fun `boots an engine when the app engine is gone and we own none`() {
        assertEquals(
            PushEngineAction.BootHeadlessEngine,
            PushEngineDecision.decide(
                appEngineAlive = false,
                headlessEngineGeneration = null,
                pluginCount = 3,
            ),
        )
    }

    @Test
    fun `boots an engine on a cold process`() {
        assertEquals(
            PushEngineAction.BootHeadlessEngine,
            PushEngineDecision.decide(
                appEngineAlive = false,
                headlessEngineGeneration = null,
                pluginCount = 0,
            ),
        )
    }

    @Test
    fun `leaves the app engine alone while it is alive`() {
        assertEquals(
            PushEngineAction.UseExistingAppEngine,
            PushEngineDecision.decide(
                appEngineAlive = true,
                headlessEngineGeneration = null,
                pluginCount = 1,
            ),
        )
    }

    @Test
    fun `leaves the app engine alone even when a headless engine exists`() {
        assertEquals(
            PushEngineAction.UseExistingAppEngine,
            PushEngineDecision.decide(
                appEngineAlive = true,
                headlessEngineGeneration = 1,
                pluginCount = 2,
            ),
        )
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
        assertEquals(
            true,
            PushEngineDecision.shouldHoldWakeLock(
                appEngineAlive = false,
                hasHeadlessEngine = true,
            ),
        )
    }

    @Test
    fun `takes no wakelock when the app engine will handle the delivery`() {
        assertEquals(
            false,
            PushEngineDecision.shouldHoldWakeLock(
                appEngineAlive = true,
                hasHeadlessEngine = true,
            ),
        )
    }

    @Test
    fun `takes no wakelock when no engine of ours exists`() {
        assertEquals(
            false,
            PushEngineDecision.shouldHoldWakeLock(
                appEngineAlive = false,
                hasHeadlessEngine = false,
            ),
        )
    }
}
