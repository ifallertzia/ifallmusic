import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// =============================================================================
// Release signing
// =============================================================================
// WHY THIS EXISTS
//   Android refuses to install an update whose signing certificate differs from
//   the one already installed, and reports it as
//   "App not installed as package conflicts with an existing package."
//   The only fix is to sign EVERY release with the SAME key. So this file reads
//   one stable release identity and never falls back to a random runner key
//   when a release identity has been supplied.
//
// WHERE CREDENTIALS COME FROM (highest priority first)
//   1. Environment variables — set by CI (.github/workflows/build.yml) after it
//      decodes the `SIGNING_KEY` secret into a TEMPORARY path outside the repo:
//        SIGNING_KEYSTORE_FILE   absolute path to the decoded .jks
//        SIGNING_KEYSTORE_TYPE   JKS (default) / PKCS12
//        SIGNING_KEY_ALIAS       e.g. upload
//        SIGNING_KEY_PASSWORD    key password
//        SIGNING_STORE_PASSWORD  keystore password
//      Short aliases KEY_ALIAS / KEY_PASSWORD / STORE_PASSWORD are also read.
//   2. android/key.properties — for local builds. This file is git-ignored.
//
// NOTHING IS HARDCODED HERE. No alias, no password and no key material is ever
// committed to this repository.
// =============================================================================

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

/** First non-blank value from [envNames], else the [propName] key.properties value. */
fun signingValue(envNames: List<String>, propName: String): String? {
    for (name in envNames) {
        val value = System.getenv(name)
        if (!value.isNullOrBlank()) return value
    }
    val fromProperties = keystoreProperties[propName] as String?
    return if (fromProperties.isNullOrBlank()) null else fromProperties
}

// Keystore location. CI points this at a temporary build path
// ($RUNNER_TEMP/signing/upload-keystore.jks) so the key never lands in the
// checkout. A relative key.properties path stays relative to android/app.
val releaseStoreFilePath: String? = signingValue(
    listOf("SIGNING_KEYSTORE_FILE", "SIGNING_KEYSTORE_PATH"),
    "storeFile",
)

val releaseStoreFile: File? = releaseStoreFilePath?.let { path ->
    val candidate = File(path)
    if (candidate.isAbsolute) candidate.normalize() else file(path).normalize()
}

// Store type: explicit env/property wins, otherwise infer from the extension.
// Being explicit matters — on JDK 9+ the platform default keystore type is
// PKCS12, and a silent type mismatch reads as a corrupt/invalid keystore.
// The path is copied into a non-null local first: script-level vals cannot be
// smart-cast, so calling endsWith() on the nullable val would not compile.
val releaseStoreType: String? = signingValue(
    listOf("SIGNING_KEYSTORE_TYPE", "SIGNING_STORE_TYPE"),
    "storeType",
) ?: run {
    val path: String = releaseStoreFilePath ?: ""
    when {
        path.isEmpty() -> null
        path.endsWith(".p12", true) || path.endsWith(".pfx", true) -> "PKCS12"
        else -> "JKS"
    }
}

val releaseKeyAlias: String? = signingValue(
    listOf("SIGNING_KEY_ALIAS", "KEY_ALIAS"),
    "keyAlias",
)
val releaseKeyPassword: String? = signingValue(
    listOf("SIGNING_KEY_PASSWORD", "KEY_PASSWORD"),
    "keyPassword",
)
val releaseStorePassword: String? = signingValue(
    listOf("SIGNING_STORE_PASSWORD", "STORE_PASSWORD"),
    "storePassword",
)

// Signing is complete only when we have a keystore file that exists plus all
// three credentials. A partial configuration is a hard error (see buildTypes).
val releaseStoreExists: Boolean = releaseStoreFile?.exists() == true
val releaseSigningComplete: Boolean = releaseStoreExists &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank() &&
    !releaseStorePassword.isNullOrBlank()

// Partial configuration is always a mistake: the operator supplied some of the
// identity, so silently signing with a different key would ship an APK that
// existing users cannot install. Fail loudly instead.
val releaseSigningConfiguredButIncomplete: Boolean =
    !releaseSigningComplete &&
        (releaseStoreFilePath != null ||
            releaseKeyAlias != null ||
            releaseKeyPassword != null ||
            releaseStorePassword != null)

if (releaseSigningConfiguredButIncomplete) {
    val missing = listOfNotNull(
        if (!releaseStoreExists) "keystore file (${releaseStoreFilePath ?: "<unset>"})" else null,
        if (releaseKeyAlias.isNullOrBlank()) "SIGNING_KEY_ALIAS" else null,
        if (releaseKeyPassword.isNullOrBlank()) "SIGNING_KEY_PASSWORD" else null,
        if (releaseStorePassword.isNullOrBlank()) "SIGNING_STORE_PASSWORD" else null,
    )
    throw GradleException(
        "Release signing is partially configured - missing: ${missing.joinToString()}. " +
            "Fix it, or unset all signing inputs. See docs/RELEASE_SIGNING.md.",
    )
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
    signingConfigs {
        create("release") {
            if (releaseSigningComplete) {
                // Explicit non-null locals: script-level vals cannot be
                // smart-cast, and assigning a nullable to these DSL properties
                // would not compile.
                val alias: String = releaseKeyAlias!!
                val keyPw: String = releaseKeyPassword!!
                val storePw: String = releaseStorePassword!!
                val store: File = releaseStoreFile!!
                keyAlias = alias
                keyPassword = keyPw
                storeFile = store
                storePassword = storePw
                // Only override when known; AGP infers the type otherwise.
                val type: String? = releaseStoreType
                if (type != null) {
                    storeType = type
                }
            }
        }
    }

    defaultConfig {
        applicationId = "com.saxify.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Version code/name come from pubspec.yaml (`version: x.y.z+build`).
        // IMPORTANT: every release MUST bump the build number, or Android will
        // not treat the new APK as an update over the installed one.
        // scripts/bump_build_number.sh and CI keep this moving automatically.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Keep one universal ABI output so the same APK works on all phones
        // (no per-ABI splits that can collide with an existing installed build).
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            if (releaseSigningComplete) {
                logger.lifecycle(
                    "Release signing: ${releaseStoreFile?.name} " +
                        "(type=$releaseStoreType, alias=$releaseKeyAlias)",
                )
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Only reachable when NO signing input was supplied at all, e.g.
                // a pull-request build on a fork with no access to secrets.
                // Tagged releases never get here: .github/workflows/build.yml
                // fails the run when the secrets are missing.
                logger.warn(
                    "WARNING: no release keystore configured - signing with the " +
                        "local debug key. This APK will NOT install over a " +
                        "release-signed build (package conflict). " +
                        "See docs/RELEASE_SIGNING.md.",
                )
                signingConfig = signingConfigs.getByName("debug")
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
