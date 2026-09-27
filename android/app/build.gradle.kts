import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing keystore properties (key.properties lives one dir up).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseStoreFilePath = keystoreProperties["storeFile"] as String?
val releaseStoreFile = releaseStoreFilePath?.let { file(it) }

android {
    namespace = "com.saxify.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // ---- signing configs ----------------------------------------------------
    // Use a stable release keystore so updates install over the old build
    // (Android rejects an update if signatures differ — that is the cause of
    // "App not installed as package conflicts with an existing package").
    signingConfigs {
        create("release") {
            if (releaseStoreFilePath != null) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = releaseStoreFile!!
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.saxify.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Version code is taken from pubspec.yaml.
        // IMPORTANT: Every release MUST bump versionCode or Android will not
        // treat the new APK as an update over the previous one.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Keep one ABI output so the same APK works on all phones (no per-ABI
        // splits that can collide with an existing installed build).
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            // Temporary, explicitly accepted fallback for APK distribution without
            // signing secrets. Runner debug keys are NOT stable across releases:
            // users may need backup/uninstall/reinstall when certificates differ.
            signingConfig = if (releaseStoreFile?.exists() == true) {
                signingConfigs.getByName("release")
            } else if (keystorePropertiesFile.exists()) {
                // Do not silently ignore a broken, explicitly configured key.
                throw GradleException("Release keystore in key.properties is missing")
            } else {
                logger.warn("No release keystore: using debug signing; in-place updates are not guaranteed.")
                signingConfigs.getByName("debug")
            }

            // Disable code shrinking for now to avoid ProGuard issues with
            // audio/download native plugins.
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
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

dependencies {
    implementation("androidx.core:core-ktx:1.16.0")
}
