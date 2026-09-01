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
// FIX v2: setting the extension-level default (above approach) was not
// enough -- sentry_flutter's own build.gradle sets languageVersion="1.6"
// directly on its KotlinCompile TASK, and task-level config always wins
// over the project's extension default. That's exactly why the error
// showed apiVersion=1.9 (nothing overrode our extension default) but
// languageVersion stuck at 1.6 (task-level override survived). Fix: force
// every KotlinCompile task's compilerOptions directly.
// FIX v3: v2 wrapped this in "afterEvaluate {}", which crashed with
// "Cannot run Project.afterEvaluate(Action) when the project is already
// evaluated" -- because the "evaluationDependsOn(:app)" line above forces
// :app to evaluate early (during some other subproject's evaluation), so
// by the time this block's own loop reached :app, it was already
// evaluated, and Gradle refuses to schedule a NEW afterEvaluate callback
// on a project that already finished evaluating.
// We still need afterEvaluate semantics (run AFTER the plugin's own
// build.gradle sets its task-level languageVersion=1.6, so our override
// applies last and wins) -- so check project.state.executed first: if
// the project already evaluated, run the config directly right now
// (safe, since "already evaluated" means the plugin's own settings are
// already in place); otherwise register the normal afterEvaluate.
subprojects {
    val applyKotlinVersionFix: Project.() -> Unit = {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
                apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
            }
        }
    }
    if (state.executed) {
        applyKotlinVersionFix()
    } else {
        afterEvaluate { applyKotlinVersionFix() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
