plugins {
    id("com.google.gms.google-services") version "4.4.4" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// FIX (build failure): sentry_flutter (and other older Flutter
// plugins pulled from pub cache) ship their own Android module with a
// Kotlin compiler config pinned to languageVersion "1.6" -- Kotlin
// 2.x (we're on 2.2.20, see settings.gradle.kts) refuses to compile
// against a language version that old ("Language version 1.6 is no
// longer supported; please, use version 1.8 or greater."), and this
// setting lives inside the PLUGIN's own build.gradle, not ours, so it
// can't be fixed by editing this repo's source. Forcing every
// subproject's Kotlin compile tasks to a modern language/API version
// here overrides whatever each plugin module set internally. This is
// the standard workaround for this exact class of error across the
// Flutter plugin ecosystem while individual plugins catch up to
// newer Kotlin Gradle Plugin versions.
subprojects {
    plugins.withId("org.jetbrains.kotlin.android") {
        extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
            compilerOptions {
                languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
                apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
