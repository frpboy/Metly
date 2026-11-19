import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional upload-keystore signing: present only on CI/release machines via
// key.properties (gitignored). Preview builds without it fall back to the
// runner debug key and stay non-store-uploadable.
val uploadKeystorePropertiesFile = rootProject.file("key.properties")
val uploadKeystoreProperties = Properties().apply {
    if (uploadKeystorePropertiesFile.exists()) {
        uploadKeystorePropertiesFile.inputStream().use { load(it) }
    }
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
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            if (uploadKeystorePropertiesFile.exists()) {
                storeFile = uploadKeystoreProperties["storeFile"]?.let { rootProject.file(it as String) }
                storePassword = uploadKeystoreProperties["storePassword"] as String?
                keyAlias = uploadKeystoreProperties["keyAlias"] as String?
                keyPassword = uploadKeystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Signed store-uploadable build when key.properties exists;
            // otherwise preview builds keep the runner debug key.
            signingConfig = if (uploadKeystorePropertiesFile.exists()) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
