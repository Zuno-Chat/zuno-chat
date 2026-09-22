package im.zuno.chat

enum class DeviceRisk(val channelName: String) {
    UNLOCKED_BOOTLOADER("unlockedBootloader"),
    ROOTED("rooted"),
}

data class AttestedBoot(val deviceLocked: Boolean, val verifiedBootState: Int)

data class BootProperties(
    val verifiedBootState: String = "",
    val flashLocked: String = "",
    val vbmetaDeviceState: String = "",
    val debuggable: String = "",
) {
    companion object {
        private val propertyLine = Regex("""^\[(.+?)]: \[(.*)]$""")

        fun fromGetprop(dump: String): BootProperties {
            val values = dump.lineSequence()
                .mapNotNull { propertyLine.matchEntire(it.trim()) }
                .associate { it.groupValues[1] to it.groupValues[2] }
            return BootProperties(
                verifiedBootState = values["ro.boot.verifiedbootstate"].orEmpty(),
                flashLocked = values["ro.boot.flash.locked"].orEmpty(),
                vbmetaDeviceState = values["ro.boot.vbmeta.device_state"].orEmpty(),
                debuggable = values["ro.debuggable"].orEmpty(),
            )
        }
    }
}

data class RootSigns(
    val suBinaryFound: Boolean,
    val rootAppInstalled: Boolean,
    val buildTags: String,
)

object DeviceSafetyDecision {
    private const val ATTESTED_UNVERIFIED = 2
    private const val ATTESTED_FAILED = 3

    fun decide(
        attested: AttestedBoot?,
        properties: BootProperties,
        rootSigns: RootSigns,
    ): Set<DeviceRisk> = buildSet {
        if (attestedUnlocked(attested) || propertiesUnlocked(properties)) {
            add(DeviceRisk.UNLOCKED_BOOTLOADER)
        }
        if (rooted(properties, rootSigns)) add(DeviceRisk.ROOTED)
    }

    private fun attestedUnlocked(attested: AttestedBoot?): Boolean {
        if (attested == null) return false
        return !attested.deviceLocked ||
            attested.verifiedBootState == ATTESTED_UNVERIFIED ||
            attested.verifiedBootState == ATTESTED_FAILED
    }

    private fun propertiesUnlocked(properties: BootProperties): Boolean =
        properties.verifiedBootState == "orange" ||
            properties.verifiedBootState == "red" ||
            properties.flashLocked == "0" ||
            properties.vbmetaDeviceState == "unlocked"

    private fun rooted(properties: BootProperties, rootSigns: RootSigns): Boolean =
        rootSigns.suBinaryFound ||
            rootSigns.rootAppInstalled ||
            rootSigns.buildTags.contains("test-keys") ||
            properties.debuggable == "1"
}
