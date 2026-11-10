plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.k4nn4n.metly"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.k4nn4n.metly"
        minSdk = 21
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Preview builds use the runner debug key; configure a persistent
            // private upload keystore before producing stable signed releases.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
