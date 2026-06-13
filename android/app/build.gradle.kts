// android/app/build.gradle.kts v7.0 — production signing via key.properties

import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load keystore credentials from android/key.properties (never commit this file)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.njtech.allin1"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    flavorDimensions += "app"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Task 1: Required by flutter_local_notifications on AGP 7+
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Matches google-services.json — change after adding allin1 app in Firebase Console
        applicationId = "com.njtech.allin1"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    productFlavors {
        create("customer") {
            dimension = "app"
            applicationId = "com.njtech.myallin1"
            manifestPlaceholders["appName"] = "my allin1"
        }
        create("hero") {
            dimension = "app"
            applicationId = "com.njtech.heroallin1"
            manifestPlaceholders["appName"] = "hero allin1"
        }
        // Task 2: Admin flavor for assembleAdminRelease
        create("admin") {
            dimension = "app"
            applicationId = "com.njtech.admininallin1"
            manifestPlaceholders["appName"] = "admin allin1"
        }
    }

    // signingConfigs MUST be declared before buildTypes
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Task 1: Required for flutter_local_notifications (Java 8+ API desugaring)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("androidx.multidex:multidex:2.0.1")
}
