import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, loaded from a properties file that is never in the repo.
//
// `android/key.properties` is gitignored; keep the real one wherever the
// keystore lives and symlink it in, so the secret has exactly one home:
//
//   ln -s /path/to/keystore/key.properties android/key.properties
//
// Absent, the release build falls back to the debug key so `flutter run
// --release` still works on a machine that has no keystore. That fallback is
// deliberate but it is not shippable: a debug-signed APK will not verify
// against assetlinks.json, so every invite opens a browser instead of the app.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.codingfries.rift"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications compiles against java.time, which does
        // not exist below API 26. Desugaring rewrites those calls to a bundled
        // backport, and the plugin refuses to build without it even for an app
        // that never schedules a notification — the check is on the dependency,
        // not on what you call. minSdk is 24, so this is two API levels of gap
        // to cover.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.codingfries.rift"
        // 24 is Flutter's own floor and also the highest any plugin here asks
        // for — flutter_local_notifications, flutter_secure_storage and
        // file_selector_android all land on it, so raising it is not needed
        // and lowering it would break those three.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "No android/key.properties - signing release with the DEBUG key. " +
                    "This build cannot be shipped: App Links will not verify."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // Version pinned by flutter_local_notifications, which declares the same
    // one for its own module. A lower one fails the AAR metadata check that
    // sent us here.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
