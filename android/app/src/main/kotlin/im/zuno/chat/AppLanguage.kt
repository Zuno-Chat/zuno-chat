package im.zuno.chat

import android.app.LocaleConfig
import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object AppLanguage {
    private const val CHANNEL = "zuno/locale"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(handler(context))
    }

    private fun handler(context: Context) = MethodChannel.MethodCallHandler { call, result ->
        if (call.method == "resolved") {
            result.success(marker(context))
            return@MethodCallHandler
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            when (call.method) {
                "get" -> result.success(mapOf("supported" to false))
                else -> result.notImplemented()
            }
            return@MethodCallHandler
        }
        val manager = context.getSystemService(LocaleManager::class.java)
        when (call.method) {
            "get" -> {
                val current = manager.applicationLocales
                result.success(
                    mapOf(
                        "supported" to true,
                        "tag" to if (current.isEmpty) null else current[0].toLanguageTag(),
                        "locale" to if (current.isEmpty) null else markerFor(context, current),
                        "options" to options(context),
                    ),
                )
            }

            "set" -> {
                val tag = call.argument<String>("tag")
                manager.applicationLocales = LocaleList.forLanguageTags(tag ?: "")
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun marker(context: Context): String = context.getString(R.string.l10n_locale)

    private fun markerFor(context: Context, locales: LocaleList): String {
        val config = Configuration(context.resources.configuration).apply { setLocales(locales) }
        return marker(context.createConfigurationContext(config))
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun options(context: Context): List<Map<String, String>> {
        val locales = LocaleConfig(context).supportedLocales ?: return emptyList()
        return (0 until locales.size()).map { index ->
            val locale = locales[index]
            mapOf(
                "tag" to locale.toLanguageTag(),
                "locale" to markerFor(context, LocaleList(locale)),
            )
        }
    }
}
