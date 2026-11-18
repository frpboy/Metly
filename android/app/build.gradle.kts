plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.k4nn4n.metly"
    compileSdk = 36

    // AGP defaults Java to 1.8 while the Kotlin plugin targets the build
    // JDK (17): align both or compileReleaseKotlin fails the consistency
    // check on CI.
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

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
