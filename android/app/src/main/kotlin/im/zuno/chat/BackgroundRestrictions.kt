package im.zuno.chat

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

object BackgroundRestrictions {
    const val CHANNEL = "zuno/background_restrictions"

    fun handler(activity: Activity) = MethodChannel.MethodCallHandler { call, result ->
        when (call.method) {
            "isIgnoringBatteryOptimizations" -> {
                result.success(
                    activity.powerManager().isIgnoringBatteryOptimizations(activity.packageName),
                )
            }

            "requestIgnoreBatteryOptimizations" -> {
                activity.startActivity(
                    packageIntent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        activity.packageName,
                    ),
                )
                result.success(null)
            }

            "isPackageIgnoringBatteryOptimizations" -> {
                val target = call.argument<String>("package")
                result.success(
                    target != null &&
                        activity.powerManager().isIgnoringBatteryOptimizations(target),
                )
            }

            "openAppSettings" -> {
                val target = call.argument<String>("package")
                if (target == null) {
                    result.error("bad_args", "package is required", null)
                    return@MethodCallHandler
                }
                activity.startActivity(
                    packageIntent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, target),
                )
                result.success(null)
            }

            "hasAutostartSettings" -> {
                result.success(autostartComponents(activity).isNotEmpty())
            }

            "openAutostartSettings" -> {
                result.success(openAutostartSettings(activity))
            }

            "isBackgroundDataRestricted" -> {
                val connectivityManager =
                    activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                result.success(
                    connectivityManager.restrictBackgroundStatus ==
                        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED,
                )
            }

            "openBackgroundDataSettings" -> {
                val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Settings.ACTION_IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS
                } else {
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                }
                activity.startActivity(packageIntent(action, activity.packageName))
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun Activity.powerManager() = getSystemService(Context.POWER_SERVICE) as PowerManager

    private fun autostartComponents(activity: Activity): List<Pair<String, String>> =
        AutostartDecision.availableFor(Build.MANUFACTURER) { (pkg, cls) ->
            activity.packageManager.resolveActivity(
                Intent().setComponent(ComponentName(pkg, cls)),
                0,
            ) != null
        }

    private fun openAutostartSettings(activity: Activity): Boolean {
        for ((pkg, cls) in autostartComponents(activity)) {
            try {
                activity.startActivity(Intent().setComponent(ComponentName(pkg, cls)))
                return true
            } catch (_: Exception) {
            }
        }
        activity.startActivity(
            packageIntent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, activity.packageName),
        )
        return false
    }

    private fun packageIntent(action: String, pkg: String) =
        Intent(action).apply { data = Uri.parse("package:$pkg") }
}
