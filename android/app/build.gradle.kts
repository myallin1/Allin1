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
    // NEW (CTO mandate — Naming Standardization): already the exact
    // shared prefix of the new com.njtech.allin1.<role> applicationId
    // family below (customer/hero/admin/seller) — no change needed here,
    // it just generates R/BuildConfig classes and doesn't need to equal
    // any single flavor's applicationId, but this value already lines up
    // logically with the new structure.
    namespace = "com.njtech.allin1"
    // FIX (build failure): receive_sharing_intent compiles against
    // Android SDK 37 -- Flutter refuses to build unless our own
    // compileSdk is at least as high as every plugin's (compileSdk is
    // backward compatible, so bumping it doesn't raise the app's real
    // minSdk/targetSdk requirements for end users).
    compileSdk = 37
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
        // NEW (CTO mandate — Naming Standardization): every flavor below
        // now overrides this with its own com.njtech.allin1.<role>
        // applicationId, so this base value is never what actually ships
        // — it only matters as the fallback/namespace-adjacent default.
        // Kept aligned with the new dot-notation family on purpose.
        applicationId = "com.njtech.allin1"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // REVERTED (build was failing — "No matching client found... in
    // google-services.json"): the full com.njtech.allin1.<role> rename
    // was only half-done on the Firebase side (only "seller" got
    // registered under the new scheme so far; customer/hero/admin were
    // never re-registered in Firebase Console under their new names).
    // Per instruction, we're matching code to what already exists in
    // Firebase/Firestore right now instead of renaming everything today:
    // customer/hero/admin go back to their ORIGINAL applicationIds
    // (already present in google-services.json), and seller keeps the
    // new com.njtech.allin1.seller id since that's the one actually
    // registered in Firebase Console (see screenshot: App ID
    // 1:357526153693:android:04dc889017e1a6774aee34). Full naming
    // standardization across all 4 flavors can be revisited later.
    productFlavors {
        create("customer") {
            dimension = "app"
            applicationId = "com.njtech.allin1"
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
        // Seller flavor for assembleSellerRelease (lib/main_seller.dart)
        create("seller") {
            dimension = "app"
            applicationId = "com.njtech.allin1.seller"
            manifestPlaceholders["appName"] = "seller allin1"
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
