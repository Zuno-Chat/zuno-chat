package im.zuno.chat.zuno_http

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProviderChoiceTest {
    private val bundled = ProviderInfo("App-Packaged-Cronet-Provider", enabled = true)
    private val httpEngine = ProviderInfo("HttpEngine-Native-Provider", enabled = true)
    private val playServices = ProviderInfo("Google-Play-Services-Cronet-Provider", enabled = true)
    private val fallback = ProviderInfo("Fallback-Cronet-Provider", enabled = true)

    @Test
    fun `the bundled copy is chosen over every other provider`() {
        assertEquals(bundled, chooseBundled(listOf(httpEngine, playServices, fallback, bundled)))
    }

    @Test
    fun `no provider is chosen when the bundled copy is disabled`() {
        assertNull(
            chooseBundled(
                listOf(httpEngine, playServices, fallback, bundled.copy(enabled = false)),
            ),
        )
    }

    @Test
    fun `the fallback is never chosen`() {
        assertNull(chooseBundled(listOf(fallback)))
    }
}
