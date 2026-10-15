import java.util.Properties

import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key lives outside the repository: android/key.properties (git-ignored)
// names the keystore and its passwords. See docs/release.md.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.iflotech.iris"
    // Pinned rather than tracking `flutter.compileSdkVersion`: that resolves to
    // 37, and the SDK installed here provides the minor-versioned `android-37.0`
    // platform, which AGP will not match against the plain `android-37` hash.
    // 36 is current and installed. Raise this once a plain android-37 is present.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.iflotech.iris"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Shrink and optimise the Java side, and drop unused resources.
            // Flutter's plugin already does this by default; stating it keeps
            // it from regressing quietly.
            isMinifyEnabled = true
            isShrinkResources = true
            // Signed with the upload key when key.properties exists. Without it
            // the release build uses the debug key so `flutter run --release`
            // still works, but Google Play will not accept that bundle.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
