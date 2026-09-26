package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AutostartDecisionTest {
    @Test
    fun `xiaomi brands open the MIUI autostart screen`() {
        val miui = "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity"
        for (brand in listOf("Xiaomi", "Redmi", "POCO")) {
            assertEquals(miui, AutostartDecision.componentsFor(brand).first())
        }
    }

    @Test
    fun `other aggressive brands have a screen to try`() {
        for (brand in listOf("OPPO", "realme", "OnePlus", "vivo", "HUAWEI", "HONOR")) {
            assertTrue(brand, AutostartDecision.componentsFor(brand).isNotEmpty())
        }
    }

    @Test
    fun `brands without an autostart screen get none`() {
        assertTrue(AutostartDecision.componentsFor("Google").isEmpty())
        assertTrue(AutostartDecision.componentsFor("samsung").isEmpty())
        assertTrue(AutostartDecision.componentsFor("").isEmpty())
    }
}
