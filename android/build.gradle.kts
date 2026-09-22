allprojects {
    repositories {
        google()
        mavenCentral()
        // light_compressor's native Android implementation
        // (com.github.AbedElazizShe:LightCompressor) is only published
        // here, not to Maven Central — see its own README.
        maven(url = "https://jitpack.io")
    }
}

// light_compressor's own android/build.gradle (in the pub cache, not
// something this project controls or can edit persistently — pub get
// would just overwrite it) predates AGP's mandatory `namespace`
// property, added in AGP 7+ and required by the AGP version this
// project is on. Its AndroidManifest.xml still declares the equivalent
// via the old `package` attribute — this just promotes that into the
// namespace AGP now insists on, rather than patching a vendored file.
// Confirmed live: the build fails immediately (before this) with
// "Namespace not specified" naming this exact module.
subprojects {
    afterEvaluate {
        if (project.name == "light_compressor") {
            extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.apply {
                if (namespace == null) {
                    namespace = "com.abedelazizshe.light_compressor"
                }
                // Its own build.gradle hardcodes compileSdkVersion 33 —
                // too old for several of its own transitive androidx
                // dependencies (lifecycle, exifinterface, ...), each
                // separately demanding 34+. Matches this app's own
                // compileSdk (android/app/build.gradle.kts) rather than
                // just the minimum they ask for.
                compileSdk = 37
                // Same root cause as the namespace fix above (an
                // unconfigured, years-stale build file) surfacing a
                // second way once the first was fixed: the Java and
                // Kotlin compile tasks disagreed on JVM target (11 vs
                // 17) — the module's own build.gradle sets neither
                // explicitly, so each toolchain fell back to its own
                // differing modern default. Pinning both to the same
                // value is what the error itself recommends.
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
            tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
