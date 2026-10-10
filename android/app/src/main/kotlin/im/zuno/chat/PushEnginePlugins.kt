package im.zuno.chat

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin

object PushEnginePlugins {
    private val factories: List<Pair<String, () -> FlutterPlugin>> = listOf(
        "flutter_local_notifications" to {
            com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin()
        },
        "flutter_secure_storage" to {
            com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin()
        },
        "package_info_plus" to { dev.fluttercommunity.plus.packageinfo.PackageInfoPlugin() },
        "path_provider" to { io.flutter.plugins.pathprovider.PathProviderPlugin() },
        "permission_handler" to { com.baseflow.permissionhandler.PermissionHandlerPlugin() },
        "shared_preferences" to { io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin() },
        "sqflite_sqlcipher" to { com.davidmartos96.sqflite_sqlcipher.SqfliteSqlCipherPlugin() },
        "sentry_flutter" to { io.sentry.flutter.SentryFlutterPlugin() },
        "jni" to { com.github.dart_lang.jni.JniPlugin() },
        "webcrypto" to { com.example.webcrypto.WebcryptoPlugin() },
        "zuno_call_style" to { im.zuno.chat.zuno_call_style.ZunoCallStylePlugin() },
        "zuno_notifications" to { im.zuno.chat.zuno_notifications.ZunoNotificationsPlugin() },
        "zuno_vibration" to { im.zuno.chat.zuno_vibration.ZunoVibrationPlugin() },
    )

    val names: List<String> get() = factories.map { it.first }

    fun create(context: Context): FlutterEngine {
        val engine = FlutterEngine(context, null, false)
        for ((name, factory) in factories) {
            try {
                engine.plugins.add(factory())
            } catch (e: Exception) {
                CaughtErrors.record(context, "push engine plugin $name", e)
            }
        }
        return engine
    }
}
