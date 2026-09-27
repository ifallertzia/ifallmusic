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
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(storeFilePath)
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
            // Sign with the stable release keystore so updates install over
            // existing builds. If the keystore file hasn't been generated yet,
            // fall back to the debug keystore and print a warning.
            val releaseStoreFilePath = keystoreProperties["storeFile"] as String?
            val releaseStoreFile = releaseStoreFilePath?.let { file(it) }
            signingConfig =
                if (releaseStoreFile != null && releaseStoreFile.exists())
                    signingConfigs.getByName("release")
                else {
                    logger.warn(
                        "WARNING: release keystore not found at android/app/upload-keystore.jks. " +
                        "Run `bash android/generate_keystore.sh` once, then rebuild. " +
                        "Falling back to debug signing for this build."
                    )
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
