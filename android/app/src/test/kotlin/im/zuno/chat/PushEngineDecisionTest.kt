package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class PushEngineDecisionTest {
    @Test
    fun `boots an engine when the app engine is gone and we own none, a cold process included`() {
        for (appEngineGeneration in listOf(3, 0)) {
            assertEquals(
                "app engines $appEngineGeneration",
                PushEngineAction.BootHeadlessEngine,
                PushEngineDecision.decide(
                    appEngineAlive = false,
                    headlessEngineGeneration = null,
                    appEngineGeneration = appEngineGeneration,
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
                    appEngineGeneration = 2,
                ),
            )
        }
    }

    @Test
    fun `reuses a headless engine when no app engine has attached since it booted`() {
        assertEquals(
            PushEngineAction.ReuseHeadlessEngine,
            PushEngineDecision.decide(
                appEngineAlive = false,
                headlessEngineGeneration = 2,
                appEngineGeneration = 2,
            ),
        )
    }

    @Test
    fun `replaces a headless engine an app engine attached after, whose plugin took the pushes`() {
        assertEquals(
            PushEngineAction.ReplaceHeadlessEngine,
            PushEngineDecision.decide(
                appEngineAlive = false,
                headlessEngineGeneration = 2,
                appEngineGeneration = 3,
            ),
        )
    }
}
