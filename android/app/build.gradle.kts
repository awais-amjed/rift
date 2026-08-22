plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
