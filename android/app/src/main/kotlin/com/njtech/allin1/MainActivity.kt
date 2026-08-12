package com.njtech.allin1

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// NEW (Aug 12 2026 — CTO mandate: "System Back Button Overhaul", all 4
// apps): Flutter has no built-in equivalent of Android's
// moveTaskToBack() — SystemNavigator.pop() (what every root screen used
// before this change) finishes/removes the Activity, which is a CLOSE,
// not a minimize, and is exactly the "app terminates / blank on
// reopen / cold-boot rebuild" bug this feature exists to fix.
//
// Deliberately a small hand-rolled MethodChannel instead of the
// move_to_background pub.dev package: that package is v1.0.2, last
// published in 2021, from an unverified publisher, and wraps this
// exact one-line native call — for a single shared MainActivity across
// all 4 flavors, writing the 15 lines ourselves removes a stale
// external dependency for zero loss of functionality.
//
// Single channel, single method, no result needed the app cares about
// (minimizing cannot meaningfully fail in a way Dart should react to),
// so the Dart side fires-and-forgets.
class MainActivity : FlutterActivity() {
    private val minimizeChannel = "com.njtech.allin1/minimize"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, minimizeChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "moveTaskToBack") {
                    // true = "non-root" flag, matching the platform API's own
                    // semantics — always safe here since we only ever call
                    // this from each app's single root/home screen.
                    moveTaskToBack(true)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}
