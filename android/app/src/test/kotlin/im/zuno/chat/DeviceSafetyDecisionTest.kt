package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class DeviceSafetyDecisionTest {
    private val lockedStock = AttestedBoot(deviceLocked = true, verifiedBootState = 0)
    private val greenProperties = BootProperties(
        verifiedBootState = "green",
        flashLocked = "1",
        vbmetaDeviceState = "locked",
        debuggable = "0",
    )
    private val unknownProperties = BootProperties()
    private val noRootSigns = RootSigns(
        suBinaryFound = false,
        rootAppInstalled = false,
        buildTags = "release-keys",
    )

    private fun decide(
        attested: AttestedBoot? = lockedStock,
        properties: BootProperties = greenProperties,
        rootSigns: RootSigns = noRootSigns,
    ) = DeviceSafetyDecision.decide(attested, properties, rootSigns)

    @Test
    fun `a locked stock device has no risks`() {
        assertEquals(emptySet<DeviceRisk>(), decide())
    }

    @Test
    fun `a relocked custom system is safe`() {
        assertEquals(
            emptySet<DeviceRisk>(),
            decide(
                attested = AttestedBoot(deviceLocked = true, verifiedBootState = 1),
                properties = greenProperties.copy(verifiedBootState = "yellow"),
            ),
        )
    }

    @Test
    fun `an attested unlocked bootloader is a risk`() {
        assertEquals(
            setOf(DeviceRisk.UNLOCKED_BOOTLOADER),
            decide(attested = AttestedBoot(deviceLocked = false, verifiedBootState = 2)),
        )
    }

    @Test
    fun `an attested unverified boot is a risk even when locked`() {
        assertEquals(
            setOf(DeviceRisk.UNLOCKED_BOOTLOADER),
            decide(attested = AttestedBoot(deviceLocked = true, verifiedBootState = 2)),
        )
    }

    @Test
    fun `an attested failed boot is a risk`() {
        assertEquals(
            setOf(DeviceRisk.UNLOCKED_BOOTLOADER),
            decide(attested = AttestedBoot(deviceLocked = true, verifiedBootState = 3)),
        )
    }

    @Test
    fun `without attestation an orange boot state is a risk`() {
        assertEquals(
            setOf(DeviceRisk.UNLOCKED_BOOTLOADER),
            decide(
                attested = null,
                properties = unknownProperties.copy(verifiedBootState = "orange"),
            ),
        )
    }

    @Test
    fun `without attestation an unlocked flash flag is a risk`() {
        assertEquals(
            setOf(DeviceRisk.UNLOCKED_BOOTLOADER),
            decide(attested = null, properties = unknownProperties.copy(flashLocked = "0")),
        )
    }

    @Test
    fun `without attestation an unlocked vbmeta state is a risk`() {
        assertEquals(
            setOf(DeviceRisk.UNLOCKED_BOOTLOADER),
            decide(
                attested = null,
                properties = unknownProperties.copy(vbmetaDeviceState = "unlocked"),
            ),
        )
    }

    @Test
    fun `an unknown boot state never warns`() {
        assertEquals(
            emptySet<DeviceRisk>(),
            decide(attested = null, properties = unknownProperties),
        )
    }

    @Test
    fun `properties still count when attestation claims locked`() {
        assertEquals(
            setOf(DeviceRisk.UNLOCKED_BOOTLOADER),
            decide(properties = greenProperties.copy(verifiedBootState = "orange")),
        )
    }

    @Test
    fun `a su binary means rooted`() {
        assertEquals(
            setOf(DeviceRisk.ROOTED),
            decide(rootSigns = noRootSigns.copy(suBinaryFound = true)),
        )
    }

    @Test
    fun `a root manager app means rooted`() {
        assertEquals(
            setOf(DeviceRisk.ROOTED),
            decide(rootSigns = noRootSigns.copy(rootAppInstalled = true)),
        )
    }

    @Test
    fun `a test-keys system build means rooted`() {
        assertEquals(
            setOf(DeviceRisk.ROOTED),
            decide(rootSigns = noRootSigns.copy(buildTags = "dev-keys,test-keys")),
        )
    }

    @Test
    fun `a debuggable system build means rooted`() {
        assertEquals(
            setOf(DeviceRisk.ROOTED),
            decide(properties = greenProperties.copy(debuggable = "1")),
        )
    }

    @Test
    fun `an unlocked and rooted device reports both risks`() {
        assertEquals(
            setOf(DeviceRisk.UNLOCKED_BOOTLOADER, DeviceRisk.ROOTED),
            decide(
                attested = AttestedBoot(deviceLocked = false, verifiedBootState = 2),
                rootSigns = noRootSigns.copy(suBinaryFound = true),
            ),
        )
    }

    @Test
    fun `boot properties are read from a getprop dump`() {
        val dump = """
            [ro.boot.flash.locked]: [0]
            [ro.boot.vbmeta.device_state]: [unlocked]
            [ro.boot.verifiedbootstate]: [orange]
            [ro.build.tags]: [release-keys]
            [ro.debuggable]: [1]
        """.trimIndent()

        assertEquals(
            BootProperties(
                verifiedBootState = "orange",
                flashLocked = "0",
                vbmetaDeviceState = "unlocked",
                debuggable = "1",
            ),
            BootProperties.fromGetprop(dump),
        )
    }

    @Test
    fun `a getprop dump without boot properties is unknown`() {
        assertEquals(
            unknownProperties,
            BootProperties.fromGetprop("[ro.build.tags]: [release-keys]\nnot a property line"),
        )
    }

    @Test
    fun `risks cross the channel under the names Dart expects`() {
        assertEquals(
            listOf("unlockedBootloader", "rooted"),
            DeviceRisk.values().map { it.channelName },
        )
    }
}
