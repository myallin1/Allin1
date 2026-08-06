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

    // NEW (CTO mandate — Naming Standardization): all 4 flavors renamed
    // from the old, inconsistent com.njtech.<role>allin1 pattern
    // (myallin1 / heroallin1 / admininallin1 / sellerallin1 — the admin
    // one even had a stray extra "in") to a single uniform
    // com.njtech.allin1.<role> dot-notation family, matching `namespace`
    // below. None of these 4 apps are live on the Play Store yet, so
    // this is a clean rename with no existing installs to migrate.
    // CTO will register these exact 4 new package names in Firebase
    // Console and replace android/app/google-services.json himself —
    // that file is intentionally NOT touched by this patch (a
    // hand-edited google-services.json would be invalid; it must come
    // from Firebase's own download).
    productFlavors {
        create("customer") {
            dimension = "app"
            applicationId = "com.njtech.allin1.customer"
            manifestPlaceholders["appName"] = "my allin1"
        }
        create("hero") {
            dimension = "app"
            applicationId = "com.njtech.allin1.hero"
            manifestPlaceholders["appName"] = "hero allin1"
        }
        // Task 2: Admin flavor for assembleAdminRelease
        create("admin") {
            dimension = "app"
            applicationId = "com.njtech.allin1.admin"
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
