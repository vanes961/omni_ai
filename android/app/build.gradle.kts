plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.omniai.omni_ai"
    compileSdk = flutter.compileSdkVersion

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

    signingConfigs {
        create("stableDebug") {
            // Use the same persisted key restored by android-test-apk.yml so APKs
            // remain upgrade-compatible across GitHub Actions runs.
            storeFile = file(System.getProperty("user.home") + "/.android/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // Keep the release APK signed with the stable CI key for upgrade compatibility.
            signingConfig = signingConfigs.getByName("stableDebug")
        }
    }
}

// The standalone torrent engine is packaged into the Android app.
val libtorrent4jCompatibilityCheck by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    implementation("org.libtorrent4j:libtorrent4j:2.0.5-22")
    implementation("org.libtorrent4j:libtorrent4j-android-arm:2.0.5-22")
    implementation("org.libtorrent4j:libtorrent4j-android-arm64:2.0.5-22")
    implementation("org.libtorrent4j:libtorrent4j-android-x86:2.0.5-22")
    implementation("org.libtorrent4j:libtorrent4j-android-x86_64:2.0.5-22")

    add("libtorrent4jCompatibilityCheck", "org.libtorrent4j:libtorrent4j:2.0.5-22")
    add("libtorrent4jCompatibilityCheck", "org.libtorrent4j:libtorrent4j-android-arm:2.0.5-22")
    add("libtorrent4jCompatibilityCheck", "org.libtorrent4j:libtorrent4j-android-arm64:2.0.5-22")
    add("libtorrent4jCompatibilityCheck", "org.libtorrent4j:libtorrent4j-android-x86:2.0.5-22")
    add("libtorrent4jCompatibilityCheck", "org.libtorrent4j:libtorrent4j-android-x86_64:2.0.5-22")
}

tasks.register("verifyLibtorrent4jArtifacts") {
    group = "verification"
    description = "Verifies the pinned libtorrent4j 2.0.5-22 base and Android ABI artifacts."
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
        logger.lifecycle("libtorrent4j 2.0.5-22 artifacts are available and declared for app runtime.")
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
