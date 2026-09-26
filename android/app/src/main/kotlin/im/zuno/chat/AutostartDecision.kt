package im.zuno.chat

object AutostartDecision {
    private val miui = listOf(
        "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
    )
    private val colorOs = listOf(
        "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
        "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
        "com.oplus.safecenter" to "com.oplus.safecenter.permission.startup.StartupAppListActivity",
    )
    private val funtouch = listOf(
        "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
        "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
    )
    private val emui = listOf(
        "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
    )

    fun componentsFor(manufacturer: String): List<Pair<String, String>> = when (manufacturer.lowercase()) {
        "xiaomi", "redmi", "poco" -> miui
        "oppo", "realme", "oneplus" -> colorOs
        "vivo", "iqoo" -> funtouch
        "huawei", "honor" -> emui
        else -> emptyList()
    }
}
