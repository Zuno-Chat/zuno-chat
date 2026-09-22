import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services") apply false
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// FCM needs a Firebase project. Its google-services.json is not in the
// repository; without it the app still builds and notifications go through
// UnifiedPush or the background service, picked in Settings.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn("google-services.json missing: building without FCM push")
}

// Release signing material, kept out of the repository (see .gitignore and
// KEYSTORE.md). Absent on a machine that only ever builds debug, which is
// this project's default per CLAUDE.md — so its absence is tolerated, but
// loudly, because the failure mode it replaces was silent: releases were
// signed with the *debug* keystore, a key every Android install shares and
// whose password is literally "android". Anyone could have built an
// accepted in-place update inheriting the sandbox, the Matrix database and
// every Megolm key in it.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseSigning = keystorePropertiesFile.exists()

android {
    namespace = "im.zuno.chat"
    // flutter.compileSdkVersion (36) is behind what flutter_secure_storage
    // requires (37); pin explicitly rather than relying on the Flutter
    // default. Safe to bump further as other plugins raise their floor.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (Calls: the ongoing-call/incoming-call
        // notifications) requires this — it ships Java 8+ APIs (java.time
        // etc.) that need desugaring support on minSdk below API 26.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "im.zuno.chat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                // v3 is off by default and is the only scheme that supports
                // signing-key *rotation* (proof-of-rotation, Android 9+).
                // Without it this keystore is the app's identity forever —
                // and KEYSTORE.md's "not recoverable" then has no escape
                // hatch at all. v2 stays on for everything below API 28;
                // v1 (JAR signing) is unnecessary above minSdk 24 and only
                // adds an attack surface. v4 is for `adb install
                // --incremental`, not distribution.
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "\n**********************************************************\n" +
                    "WARNING: android/key.properties not found.\n" +
                    "This release build is signed with the DEBUG key, which is\n" +
                    "public and shared by every Android SDK install. Do NOT\n" +
                    "distribute it. See KEYSTORE.md.\n" +
                    "**********************************************************\n"
                )
                signingConfigs.getByName("debug")
            }
            // R8: shrink and obfuscate. Dart is AOT-compiled and unaffected,
            // but this covers the Kotlin/Java side and every plugin's.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// unifiedpush_android's own native dependency (org.unifiedpush.android:
// connector, for the Web Push message encryption UnifiedPush's onMessage
// automatically decrypts) pulls in plain com.google.crypto.tink:tink;
// flutter_secure_storage already pulls in com.google.crypto.tink:
// tink-android — the Android-optimized variant of the exact same
// classes. Both on the classpath at once fails the build outright
// ("Duplicate class ... found in modules tink-1.23.0.jar ... and
// tink-android-1.23.0.jar"), confirmed live via `flutter build apk`.
// Excluding the plain one keeps the Android-appropriate variant that was
// already a dependency, rather than pinning/forcing a specific version of
// either — same category of plugin-vs-plugin Gradle conflict as
// light_compressor's own patching, just resolved with an exclude instead
// of a version pin.
configurations.all {
    exclude(group = "com.google.crypto.tink", module = "tink")
}

dependencies {
    // PushEngineDecisionTest — plain JVM unit tests (no Android types in
    // PushEngineDecision, deliberately, so this needs no Robolectric or
    // connected device). Run with:
    //   cd android && ./gradlew :app:testDebugUnitTest
    testImplementation("junit:junit:4.13.2")
    // ShortcutInfoCompat/ShortcutManagerCompat/IconCompat, for the "Add to
    // home screen" pinned-shortcut MethodChannel in MainActivity. Likely
    // already present transitively via the Flutter embedding, but declared
    // explicitly rather than relying on that.
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.exifinterface:exifinterface:1.4.1")
    // GoogleApiAvailability + makeGooglePlayServicesAvailable, for the
    // Play Services probe MethodChannel in MainActivity. Present at runtime
    // transitively via firebase-messaging, but that only pulls
    // play-services-basement (GoogleApiAvailabilityLight, which has no
    // makeGooglePlayServicesAvailable) — so it has to be declared here to
    // be on the compile classpath.
    implementation("com.google.android.gms:play-services-base:18.5.0")
    // Required by compileOptions.isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
