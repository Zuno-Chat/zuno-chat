# R8 is enabled on release builds (see build.gradle.kts). Dart code is
# AOT-compiled and untouched by this; these rules cover the Kotlin/Java
# side, where several plugins are reached reflectively and so look unused
# to static analysis.

# flutter_local_notifications: ActionBroadcastReceiver is named as a string
# in a PendingIntent (and declared in AndroidManifest.xml), never called
# from Kotlin — the ring notification's Decline action routes through it.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends com.dexterous.flutterlocalnotifications.** { *; }

# Its notification payloads are (de)serialized with Gson, which needs the
# generic signatures and field names intact.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# This app's own MainActivity/services are referenced from the manifest and
# from MethodChannel names, not from Kotlin call sites.
-keep class im.zuno.chat.** { *; }

# flutter_webrtc reaches org.webrtc from native/JNI.
-keep class org.webrtc.** { *; }

# UnifiedPush's connector cold-boots the Dart entrypoint from its own
# service; keep the plugin surface it resolves by name.
-keep class org.unifiedpush.** { *; }

# Firebase Messaging reaches its service by manifest name and reads
# annotated components reflectively; R8 cannot see either.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
