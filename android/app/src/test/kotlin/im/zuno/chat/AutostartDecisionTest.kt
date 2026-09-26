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
    fun `a xiaomi phone without the MIUI screen, such as one on LineageOS, gets none`() {
        assertTrue(AutostartDecision.availableFor("Xiaomi") { false }.isEmpty())
    }

    @Test
    fun `only the screens that exist on the phone are offered`() {
        val oplus = "com.oplus.safecenter" to "com.oplus.safecenter.permission.startup.StartupAppListActivity"
        assertEquals(listOf(oplus), AutostartDecision.availableFor("OnePlus") { it == oplus })
    }

    @Test
    fun `stock MIUI keeps its autostart screen`() {
        val miui = "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity"
        assertEquals(listOf(miui), AutostartDecision.availableFor("Xiaomi") { true })
    }

    @Test
    fun `brands without an autostart screen get none`() {
        assertTrue(AutostartDecision.componentsFor("Google").isEmpty())
        assertTrue(AutostartDecision.componentsFor("samsung").isEmpty())
        assertTrue(AutostartDecision.componentsFor("").isEmpty())
    }
}
