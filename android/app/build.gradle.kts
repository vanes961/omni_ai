plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.omniai.omni_ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.omniai.omni_ai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // llama_flutter_android requires Android API 26 or newer.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Resolve the exact candidate artifacts in CI without packaging them into the app yet.
// This verifies Maven coordinates and publication availability without increasing APK size.
val libtorrent4jCompatibilityCheck by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    add("libtorrent4jCompatibilityCheck", "org.libtorrent4j:libtorrent4j:2.0.5-22")
    add("libtorrent4jCompatibilityCheck", "org.libtorrent4j:libtorrent4j-android-arm:2.0.5-22")
    add("libtorrent4jCompatibilityCheck", "org.libtorrent4j:libtorrent4j-android-arm64:2.0.5-22")
    add("libtorrent4jCompatibilityCheck", "org.libtorrent4j:libtorrent4j-android-x86:2.0.5-22")
    add("libtorrent4jCompatibilityCheck", "org.libtorrent4j:libtorrent4j-android-x86_64:2.0.5-22")
}

tasks.register("verifyLibtorrent4jArtifacts") {
    group = "verification"
    description = "Resolves the pinned libtorrent4j 2.0.5-22 base and Android ABI artifacts without packaging them."
    doLast {
        val artifacts = libtorrent4jCompatibilityCheck.resolve()
        val expectedNames = setOf(
            "libtorrent4j-2.0.5-22.jar",
            "libtorrent4j-android-arm-2.0.5-22.jar",
            "libtorrent4j-android-arm64-2.0.5-22.jar",
            "libtorrent4j-android-x86-2.0.5-22.jar",
            "libtorrent4j-android-x86_64-2.0.5-22.jar",
        )
        val actualNames = artifacts.map { it.name }.toSet()
        check(actualNames.containsAll(expectedNames)) {
            "Missing libtorrent4j artifacts. Expected $expectedNames but resolved $actualNames"
        }
        artifacts.sortedBy { it.name }.forEach { artifact ->
            check(artifact.isFile && artifact.length() > 0L) {
                "Resolved libtorrent4j artifact is empty or missing: ${artifact.name}"
            }
            logger.lifecycle("Resolved ${artifact.name}: ${artifact.length()} bytes")
        }
        logger.lifecycle("libtorrent4j 2.0.5-22 artifact resolution passed; no artifacts were added to app runtime.")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
