package com.njtech.allin1

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val minimizeChannel = "com.njtech.allin1/minimize"
    private val accessibilityChannel = "com.njtech.allin1/accessibility"

    companion object {
        @JvmField
        var voiceCommandCallback: ((String) -> Unit)? = null

        @JvmField
        var callStateCallback: ((String, String, String?) -> Unit)? = null

        @JvmField
        var assistTriggerCallback: (() -> Unit)? = null

        @JvmField
        var smsReceivedCallback: ((String, String) -> Unit)? = null
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        maybeWakeOverLockScreen(intent)
        maybeHandleAssistTrigger(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        maybeWakeOverLockScreen(intent)
        maybeHandleAssistTrigger(intent)

        val voiceCmd = intent.getStringExtra("voice_command")
        if (!voiceCmd.isNullOrEmpty()) {
            intent.removeExtra("voice_command")
            voiceCommandCallback?.invoke(voiceCmd)
        }
    }

    // Companion to maybeWakeOverLockScreen — the same ChittiVoiceInteractionSession
    // launch also carries this extra so Flutter opens straight into the
    // panel with the mic already listening (GuruOverlayService.show(
    // autoStartMic: true) — see ChittiAccessibilityBridge.onAssistTriggered),
    // matching what a wake-word trigger will eventually do once Picovoice
    // is wired in.
    private fun maybeHandleAssistTrigger(intent: Intent?) {
        if (intent?.getBooleanExtra("assist_trigger", false) != true) return
        intent.removeExtra("assist_trigger")
        assistTriggerCallback?.invoke()
    }

    // FIX (Aug 30 2026 — real security regression found mid-feature-build):
    // this used to run setShowWhenLocked/setTurnScreenOn/requestDismissKeyguard
    // UNCONDITIONALLY in onCreate/onNewIntent — on EVERY launch, in EVERY
    // flavor (this file is shared across customer/hero/seller/admin, not
    // admin-only). That meant a real customer opening the app from a
    // locked phone would have the app try to draw over their lock screen
    // and dismiss it, on every single launch — nothing to do with the
    // voice-assistant wake feature this was written for. Gated behind an
    // explicit "assist_wake" intent extra so ONLY the intentional
    // assistant-trigger path (ChittiVoiceInteractionSession, admin-only)
    // gets this behavior; a normal app launch/resume is untouched.
    private fun maybeWakeOverLockScreen(intent: Intent?) {
        if (intent?.getBooleanExtra("assist_wake", false) != true) return
        intent.removeExtra("assist_wake")

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        val km = getSystemService(android.content.Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            km.requestDismissKeyguard(this, null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Minimize task channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, minimizeChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "moveTaskToBack") {
                    moveTaskToBack(true)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

        // Accessibility & call service channel (uses Reflection for compilation decoupling)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, accessibilityChannel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestCallPermissions" -> {
                    val permissions = arrayOf(
                        android.Manifest.permission.READ_PHONE_STATE,
                        android.Manifest.permission.ANSWER_PHONE_CALLS,
                        android.Manifest.permission.RECORD_AUDIO,
                        android.Manifest.permission.READ_CALL_LOG
                    )
                    val toRequest = permissions.filter {
                        androidx.core.content.ContextCompat.checkSelfPermission(this, it) != android.content.pm.PackageManager.PERMISSION_GRANTED
                    }
                    if (toRequest.isNotEmpty()) {
                        androidx.core.app.ActivityCompat.requestPermissions(this, toRequest.toTypedArray(), 101)
                    }
                    result.success(true)
                }
                "checkCallPermissions" -> {
                    val readPhone = androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_PHONE_STATE) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    val answerCalls = androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.ANSWER_PHONE_CALLS) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    val recordAudio = androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    val readCallLog = androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_CALL_LOG) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    result.success(mapOf(
                        "readPhone" to readPhone,
                        "answerCalls" to answerCalls,
                        "recordAudio" to recordAudio,
                        "readCallLog" to readCallLog
                    ))
                }
                "isPermissionGranted" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "checkOverlayPermission" -> {
                    val canDraw = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(canDraw)
                }
                "requestOverlayPermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        if (!Settings.canDrawOverlays(this)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                android.net.Uri.parse("package:$packageName")
                            ).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        }
                    }
                    result.success(true)
                }
                "getActiveCallState" -> {
                    try {
                        val serviceClass = Class.forName("com.njtech.allin1.PhoneCallService")
                        val stateField = serviceClass.getField("activeCallState")
                        val numberField = serviceClass.getField("activeCallerNumber")
                        val state = stateField.get(null) as? String
                        val number = numberField.get(null) as? String
                        if (state != null && number != null) {
                            result.success(mapOf("event" to state, "number" to number))
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                // Returns the native speaker-route DIAGNOSTICS string
                // rather than a bare true (Aug 31 2026 — Nizam: "innum
                // hearing la mattum than kekuthu"). The previous version
                // returned true unconditionally even when the route
                // silently failed, which is exactly why three rounds of
                // debugging had no data to work from. Dart logs whatever
                // comes back into chitti_screening_debug_logs.
                "enableSpeakerphone" -> {
                    try {
                        val serviceClass = Class.forName("com.njtech.allin1.PhoneCallService")
                        val method = serviceClass.getMethod("enableSpeakerphone", android.content.Context::class.java)
                        val instance = try { serviceClass.getField("INSTANCE").get(null) } catch (e: Exception) { null }
                        method.invoke(instance, this)
                        val diagField = serviceClass.getField("lastSpeakerDiagnostics")
                        val diagnostics = diagField.get(instance) as? String ?: "unavailable"
                        result.success(diagnostics)
                    } catch (e: Exception) {
                        try {
                            val audioManager = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
                            audioManager.mode = android.media.AudioManager.MODE_IN_COMMUNICATION
                            audioManager.isSpeakerphoneOn = true
                        } catch (ex: Exception) {}
                        result.success("PhoneCallService unavailable (${e.message}) — AudioManager fallback only")
                    }
                }
                "resetAudioMode" -> {
                    try {
                        val serviceClass = Class.forName("com.njtech.allin1.PhoneCallService")
                        val method = serviceClass.getMethod("resetAudioMode", android.content.Context::class.java)
                        val instance = try { serviceClass.getField("INSTANCE").get(null) } catch (e: Exception) { null }
                        method.invoke(instance, this)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val audioManager = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
                            audioManager.mode = android.media.AudioManager.MODE_NORMAL
                            audioManager.isSpeakerphoneOn = false
                        } catch (ex: Exception) {}
                        result.success(true)
                    }
                }
                "openSettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    result.success(true)
                }
                "clickElement" -> {
                    val text = call.argument<String>("text") ?: ""
                    val service = getAccessibilityServiceInstance()
                    if (service != null) {
                        try {
                            val method = service.javaClass.getMethod("performClick", String::class.java)
                            result.success(method.invoke(service, text) as Boolean)
                        } catch (e: Exception) {
                            result.error("REFLECTION_ERROR", e.message, null)
                        }
                    } else {
                        result.error("SERVICE_UNAVAILABLE", "Accessibility Service is not running", null)
                    }
                }
                "inputText" -> {
                    val label = call.argument<String>("label") ?: ""
                    val text = call.argument<String>("text") ?: ""
                    val service = getAccessibilityServiceInstance()
                    if (service != null) {
                        try {
                            val method = service.javaClass.getMethod("performInput", String::class.java, String::class.java)
                            result.success(method.invoke(service, label, text) as Boolean)
                        } catch (e: Exception) {
                            result.error("REFLECTION_ERROR", e.message, null)
                        }
                    } else {
                        result.error("SERVICE_UNAVAILABLE", "Accessibility Service is not running", null)
                    }
                }
                "scroll" -> {
                    val direction = call.argument<String>("direction") ?: "down"
                    val service = getAccessibilityServiceInstance()
                    if (service != null) {
                        try {
                            val method = service.javaClass.getMethod("performScroll", String::class.java)
                            result.success(method.invoke(service, direction) as Boolean)
                        } catch (e: Exception) {
                            result.error("REFLECTION_ERROR", e.message, null)
                        }
                    } else {
                        result.error("SERVICE_UNAVAILABLE", "Accessibility Service is not running", null)
                    }
                }
                "goBack" -> {
                    val service = getAccessibilityServiceInstance()
                    if (service != null) {
                        try {
                            val method = service.javaClass.getMethod("performGlobalAction", Int::class.javaPrimitiveType ?: Int::class.java)
                            result.success(method.invoke(service, android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK) as Boolean)
                        } catch (e: Exception) {
                            result.error("REFLECTION_ERROR", e.message, null)
                        }
                    } else {
                        result.error("SERVICE_UNAVAILABLE", "Accessibility Service is not running", null)
                    }
                }
                "goHome" -> {
                    val service = getAccessibilityServiceInstance()
                    if (service != null) {
                        try {
                            val method = service.javaClass.getMethod("performGlobalAction", Int::class.javaPrimitiveType ?: Int::class.java)
                            result.success(method.invoke(service, android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME) as Boolean)
                        } catch (e: Exception) {
                            result.error("REFLECTION_ERROR", e.message, null)
                        }
                    } else {
                        result.error("SERVICE_UNAVAILABLE", "Accessibility Service is not running", null)
                    }
                }
                "readScreen" -> {
                    val service = getAccessibilityServiceInstance()
                    if (service != null) {
                        try {
                            val method = service.javaClass.getMethod("readScreen")
                            result.success(method.invoke(service) as String)
                        } catch (e: Exception) {
                            result.error("REFLECTION_ERROR", e.message, null)
                        }
                    } else {
                        result.error("SERVICE_UNAVAILABLE", "Accessibility Service is not running", null)
                    }
                }
                "launchApp" -> {
                    val appLabel = call.argument<String>("label") ?: ""
                    val pm = packageManager
                    val apps = pm.getInstalledApplications(0)
                    var targetPackage: String? = null
                    for (app in apps) {
                        val name = pm.getApplicationLabel(app).toString()
                        if (name.equals(appLabel, ignoreCase = true)) {
                            targetPackage = app.packageName
                            break
                        }
                    }
                    if (targetPackage != null) {
                        val launchIntent = pm.getLaunchIntentForPackage(targetPackage)
                        if (launchIntent != null) {
                            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(launchIntent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "sendSms" -> {
                    val number = call.argument<String>("number") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    if (number.isNotEmpty() && message.isNotEmpty()) {
                        try {
                            val smsManager = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                                getSystemService(android.telephony.SmsManager::class.java)
                            } else {
                                @Suppress("DEPRECATION")
                                android.telephony.SmsManager.getDefault()
                            }
                            val parts = smsManager.divideMessage(message)
                            if (parts.size > 1) {
                                smsManager.sendMultipartTextMessage(number, null, parts, null, null)
                            } else {
                                smsManager.sendTextMessage(number, null, message, null, null)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SMS_SEND_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Phone number and message must not be empty", null)
                    }
                }
                // NEW (Aug 31 2026 — Option A: default-dialer role for
                // real call-speaker control). Same reflection-free
                // pattern as the rest of this channel — these two are
                // plain Android APIs, no PhoneCallService involvement,
                // so no reflection decoupling is needed. Polled from
                // Flutter the same way accessibilityServiceEnabled is
                // (checked again on app resume), since the actual grant
                // happens in a system dialog this app doesn't control
                // the result of directly.
                "isDefaultDialer" -> {
                    try {
                        val telecomManager = getSystemService(android.telecom.TelecomManager::class.java)
                        result.success(telecomManager?.defaultDialerPackage == packageName)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                // FIX (Sep 1 2026 — Nizam: "button-ah tap pannamudida
                // athu dummy-ya than iruku"). This used to fire
                // startActivity() and blindly return success(true) even
                // when isRoleAvailable() was false or roleManager was
                // null — exactly a silent no-op that LOOKS like a dead
                // button. Now returns a real status string Dart can show
                // (same diagnostics-over-guessing discipline as the
                // speaker-route fix), and falls back to the OS's own
                // "Default apps" settings screen — which lets the admin
                // set Chitti as Phone app manually — whenever the direct
                // role-request path isn't available or throws.
                "requestDefaultDialerRole" -> {
                    var outcome = "unknown"
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                            val roleManager = getSystemService(android.app.role.RoleManager::class.java)
                            when {
                                roleManager == null -> outcome = "RoleManager unavailable on this device"
                                roleManager.isRoleHeld(android.app.role.RoleManager.ROLE_DIALER) -> outcome = "already held"
                                !roleManager.isRoleAvailable(android.app.role.RoleManager.ROLE_DIALER) -> {
                                    outcome = "ROLE_DIALER not available on this device — opened Default Apps settings instead"
                                    openDefaultAppsSettingsFallback()
                                }
                                else -> {
                                    val roleIntent = roleManager.createRequestRoleIntent(android.app.role.RoleManager.ROLE_DIALER)
                                    startActivity(roleIntent)
                                    outcome = "role request dialog launched"
                                }
                            }
                        } else {
                            @Suppress("DEPRECATION")
                            val changeIntent = Intent(android.telecom.TelecomManager.ACTION_CHANGE_DEFAULT_DIALER).apply {
                                putExtra(android.telecom.TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, packageName)
                            }
                            startActivity(changeIntent)
                            outcome = "legacy change-dialer dialog launched (pre-Android 10)"
                        }
                    } catch (e: Exception) {
                        outcome = "threw ${e.javaClass.simpleName}: ${e.message} — opened Default Apps settings instead"
                        openDefaultAppsSettingsFallback()
                    }
                    result.success(outcome)
                }
                "getRecentSms" -> {
                    try {
                        val prefs = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
                        val rawJson = prefs.getString("flutter.chitti_recent_sms_log", "[]") ?: "[]"
                        result.success(rawJson)
                    } catch (e: Exception) {
                        result.error("SMS_READ_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Setup listener for incoming voice commands from the floating bubble
        voiceCommandCallback = { command ->
            runOnUiThread {
                channel.invokeMethod("onVoiceCommand", mapOf("command" to command))
            }
        }

        // Setup listener for phone call state changes
        callStateCallback = { event, number, recordingPath ->
            runOnUiThread {
                channel.invokeMethod("onCallStateChanged", mapOf("event" to event, "number" to number, "recordingPath" to recordingPath))
            }
        }

        // Setup listener for the assistant-gesture trigger (ChittiVoiceInteractionSession)
        assistTriggerCallback = {
            runOnUiThread {
                channel.invokeMethod("onAssistTriggered", null)
            }
        }

        // Setup listener for incoming SMS messages
        smsReceivedCallback = { sender, body ->
            runOnUiThread {
                channel.invokeMethod("onSmsReceived", mapOf("sender" to sender, "body" to body))
            }
        }

        // Cold-start check: If MainActivity is booting while a voice command arrived from the floating bubble
        val bootVoiceCmd = intent?.getStringExtra("voice_command")
        if (!bootVoiceCmd.isNullOrEmpty()) {
            intent?.removeExtra("voice_command")
            runOnUiThread {
                channel.invokeMethod("onVoiceCommand", mapOf("command" to bootVoiceCmd))
            }
        }

        // Cold-start check: same recovery for the assist-gesture trigger —
        // onCreate() may have already run and found no listener attached
        // yet if the engine was still cold-booting.
        val bootAssistTrigger = intent?.getBooleanExtra("assist_trigger", false) == true
        if (bootAssistTrigger) {
            intent?.removeExtra("assist_trigger")
            runOnUiThread {
                channel.invokeMethod("onAssistTriggered", null)
            }
        }

        // Cold-start check: If MainActivity is booting while a call was just accepted,
        // retrieve the cached state and invoke the Dart channel immediately.
        try {
            val serviceClass = Class.forName("com.njtech.allin1.PhoneCallService")
            val stateField = serviceClass.getField("activeCallState")
            val numberField = serviceClass.getField("activeCallerNumber")
            val state = stateField.get(null) as? String
            val number = numberField.get(null) as? String
            if (state == "connected" && !number.isNullOrEmpty()) {
                stateField.set(null, null)
                runOnUiThread {
                    channel.invokeMethod("onCallStateChanged", mapOf("event" to "connected", "number" to number))
                }
            }
        } catch (e: Exception) {
            // Safe fallback for other flavors where PhoneCallService doesn't exist
        }
    }

    // NEW (Sep 1 2026 — "button dummy" fix). Manual escape hatch to the
    // OS's own "Default apps" list, which lets the admin pick Chitti as
    // the Phone app by hand regardless of why the direct RoleManager
    // request didn't fire a dialog. Location varies a little by OEM
    // skin, but this intent (added in API 24) is the standard entry
    // point on stock and most custom Android builds.
    private fun openDefaultAppsSettingsFallback() {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK })
            } catch (_: Exception) {}
        }
    }

    private fun getAccessibilityServiceInstance(): Any? {
        return try {
            val clazz = Class.forName("com.njtech.allin1.ChittiAccessibilityService")
            val field = clazz.getField("instance")
            field.get(null)
        } catch (e: Exception) {
            null
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        return try {
            val serviceClass = Class.forName("com.njtech.allin1.ChittiAccessibilityService")
            val expectedComponentName = ComponentName(this, serviceClass)
            val enabledServices = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val colonSplitter = TextUtils.SimpleStringSplitter(':')
            colonSplitter.setString(enabledServices)
            while (colonSplitter.hasNext()) {
                val componentNameString = colonSplitter.next()
                val enabledComponent = ComponentName.unflattenFromString(componentNameString)
                if (enabledComponent != null && enabledComponent == expectedComponentName) {
                    return true
                }
            }
            false
        } catch (e: Exception) {
            false
        }
    }

    override fun onDestroy() {
        voiceCommandCallback = null
        callStateCallback = null
        assistTriggerCallback = null
        smsReceivedCallback = null
        super.onDestroy()
    }
}
