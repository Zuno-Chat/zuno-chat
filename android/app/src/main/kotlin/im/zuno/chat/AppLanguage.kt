package im.zuno.chat

import android.app.LocaleManager
import android.content.Context
import android.os.Build
import android.os.LocaleList
import io.flutter.plugin.common.MethodChannel

object AppLanguage {
    const val CHANNEL = "zuno/locale"

    fun handler(context: Context) = MethodChannel.MethodCallHandler { call, result ->
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
}
