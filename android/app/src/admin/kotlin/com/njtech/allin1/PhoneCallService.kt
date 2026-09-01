package com.njtech.allin1

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object PhoneCallService {
    private const val IN_CALL_NOTIFICATION_CHANNEL_ID = "chitti_in_call_controls"
    private const val IN_CALL_NOTIFICATION_ID = 4271

    // NEW (Aug 31 2026 — Option A, default-dialer role): the live
    // Telecom Call object, handed to us by ChittiInCallService once
    // Chitti holds the Phone role and Android starts binding it for
    // real calls. Needed only to hang up / read state from the
    // notification actions below — the actual speaker routing goes
    // through ChittiInCallService.instance (setAudioRoute is a method
    // on the SERVICE, not the Call).
    @Volatile
    private var activeTelecomCall: Call? = null

    @Volatile
    private var speakerOnViaTelecom = false

    // NEW (Aug 31 2026 — Nizam: "innum hearing la mattum than kekuthu").
    // The previous round's speaker work logged ONLY to Logcat, so the
    // in-app debug screen could not show whether the Telecom route was
    // even attempted, let alone why it failed. Without this the next
    // step would be another guess. Captured on every enableSpeakerphone()
    // call and read back over the method channel so it lands in
    // chitti_screening_debug_logs alongside the TTS lines.
    @Volatile
    @JvmField
    var lastSpeakerDiagnostics: String = "not attempted yet"

    // Reports the four things that decide whether a real call can be put
    // on speaker at all — each one a yes/no the admin (and Chitti) can
    // act on, instead of a single opaque "it didn't work".
    private fun buildSpeakerDiagnostics(context: Context, routedViaTelecom: Boolean): String {
        val isDefaultDialer = try {
            val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            tm.defaultDialerPackage == context.packageName
        } catch (e: Exception) {
            false
        }
        val serviceBound = ChittiInCallService.instance != null
        val hasTelecomCall = activeTelecomCall != null
        return "isDefaultDialer=$isDefaultDialer, inCallServiceBound=$serviceBound, " +
            "hasLiveTelecomCall=$hasTelecomCall, setAudioRoute(SPEAKER)=$routedViaTelecom"
    }
    private var isRinging = false
    private var incomingNumber = ""
    private val handler = Handler(Looper.getMainLooper())
    private var answerRunnable: Runnable? = null

    private var wasAutoAnswered = false

    private var mediaRecorder: MediaRecorder? = null
    private var currentRecordingPath: String? = null

    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_WAS_AUTO_ANSWERED = "chitti_native_was_auto_answered"
    private const val KEY_PENDING_NUMBER = "chitti_native_pending_caller_number"

    @JvmField
    var activeCallState: String? = null

    @JvmField
    var activeCallerNumber: String? = null

    fun onCallRinging(context: Context, number: String) {
        if (isRinging) return
        isRinging = true
        incomingNumber = number
        wasAutoAnswered = false
        activeCallState = "ringing"
        activeCallerNumber = number
        clearPersistedAutoAnswerFlag(context)
        Log.d("PhoneCallService", "Incoming call ringing from: $number. Scheduling auto-answer in 20s.")

        // Schedule auto-answering after 20 seconds delay
        answerRunnable = Runnable {
            Log.d("PhoneCallService", "20s elapsed. Auto-answering incoming call now.")
            answerCall(context)
        }
        handler.postDelayed(answerRunnable!!, 20000)
    }

    fun onCallConnected(context: Context) {
        answerRunnable?.let { handler.removeCallbacks(it) }
        val wasAuto = wasAutoAnswered || readPersistedAutoAnswerFlag(context)
        val number = incomingNumber.ifEmpty { readPersistedNumber(context) }
        isRinging = false
        Log.d("PhoneCallService", "Call connected. wasAutoAnswered(memory)=$wasAutoAnswered wasAuto(resolved)=$wasAuto")

        if (wasAuto) {
            activeCallState = "connected"
            activeCallerNumber = number

            // ORDER FIX (Aug 31 2026 — Nizam: "Oppo la loud speaker on
            // agala"). Call recording (startRecording, below) claims the
            // mic via MediaRecorder.AudioSource.MIC. Doing that BEFORE
            // the audio-mode/route switch meant the speaker-routing call
            // (enableSpeakerphone) was negotiating a route change while
            // something else already held the mic — exactly the kind of
            // conflict OEM audio stacks (ColorOS especially) are known to
            // silently drop rather than error on. Committing the
            // speaker route FIRST, then starting the recorder after,
            // removes that race: by the time MediaRecorder opens the
            // mic, AudioManager has already settled on the speaker as
            // the communication device.
            enableSpeakerphone(context)

            // Start native call recording (now after the route is set)
            startRecording(context, number)

            // Wake up MainActivity to ensure Flutter Engine is running
            launchMainActivity(context)

            // Notify Flutter via reflection (if MainActivity is already registered)
            triggerFlutterCallState("connected", number, null)
        } else {
            Log.d("PhoneCallService", "Call was answered manually by Nizam. Chitti screening bypassed.")
        }
    }

    fun onCallEnded(context: Context) {
        isRinging = false
        answerRunnable?.let { handler.removeCallbacks(it) }
        Log.d("PhoneCallService", "Call ended. Finalizing recording and resetting audio.")

        activeCallState = null
        activeCallerNumber = null

        // Stop and finalize call audio recording
        val recordingPath = stopRecording(context)

        // Restore standard audio settings
        resetAudioMode(context)

        // Notify Flutter via reflection with the recording path
        triggerFlutterCallState("ended", incomingNumber, recordingPath)
        clearPersistedAutoAnswerFlag(context)
        incomingNumber = ""
        wasAutoAnswered = false
    }

    private fun startRecording(context: Context, callerNumber: String) {
        try {
            val yearMonth = SimpleDateFormat("yyyy/MM", Locale.US).format(Date())
            val dir = context.getExternalFilesDir("Allin1_Calls/$yearMonth")
                ?: File(context.filesDir, "Allin1_Calls/$yearMonth")
            if (!dir.exists()) dir.mkdirs()
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val cleanNumber = callerNumber.replace(Regex("[^0-9+]"), "").ifEmpty { "unknown" }
            val file = File(dir, "Call_${cleanNumber}_${timestamp}.m4a")
            currentRecordingPath = file.absolutePath

            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioEncodingBitRate(64000)
            recorder.setAudioSamplingRate(44100)
            recorder.setOutputFile(file.absolutePath)
            recorder.prepare()
            recorder.start()
            Log.d("PhoneCallService", "Call recording started at: ${file.absolutePath}")
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to start call recording: ${e.message}")
            mediaRecorder = null
            currentRecordingPath = null
        }
    }

    private fun stopRecording(context: Context? = null): String? {
        val path = currentRecordingPath
        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
            Log.d("PhoneCallService", "Call recording stopped successfully: $path")

            // On Android 10+ (Q+), also publish to MediaStore so it appears in Music/Voice Recorder apps
            if (path != null && context != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    val srcFile = File(path)
                    if (srcFile.exists() && srcFile.length() > 0) {
                        val yearMonth = SimpleDateFormat("yyyy/MM", Locale.US).format(Date())
                        val values = android.content.ContentValues().apply {
                            put(android.provider.MediaStore.Audio.Media.DISPLAY_NAME, srcFile.name)
                            put(android.provider.MediaStore.Audio.Media.MIME_TYPE, "audio/mp4")
                            put(android.provider.MediaStore.Audio.Media.RELATIVE_PATH, "Recordings/Allin1_Calls/$yearMonth")
                            put(android.provider.MediaStore.Audio.Media.IS_PENDING, 1)
                        }
                        val uri = context.contentResolver.insert(android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                        if (uri != null) {
                            context.contentResolver.openOutputStream(uri)?.use { out ->
                                java.io.FileInputStream(srcFile).use { input ->
                                    input.copyTo(out)
                                }
                            }
                            values.clear()
                            values.put(android.provider.MediaStore.Audio.Media.IS_PENDING, 0)
                            context.contentResolver.update(uri, values, null, null)
                            Log.d("PhoneCallService", "Published recording to MediaStore: $uri")
                        }
                    }
                } catch (e: Exception) {
                    Log.d("PhoneCallService", "Could not publish to MediaStore: ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Error stopping call recording: ${e.message}")
        } finally {
            mediaRecorder = null
            currentRecordingPath = null
        }
        return path
    }

    private fun answerCall(context: Context) {
        try {
            val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                wasAutoAnswered = true
                persistAutoAnswerFlag(context, incomingNumber)
                telecomManager.acceptRingingCall()
                Log.d("PhoneCallService", "acceptRingingCall() successfully executed")

                // Launch MainActivity immediately to start cold booting the engine
                launchMainActivity(context)
            }
        } catch (e: SecurityException) {
            Log.e("PhoneCallService", "ANSWER_PHONE_CALLS permission not granted: ${e.message}")
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Error accepting call programmatically: ${e.message}")
        }
    }

    private fun persistAutoAnswerFlag(context: Context, number: String) {
        try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_WAS_AUTO_ANSWERED, true)
                .putString(KEY_PENDING_NUMBER, number)
                .apply()
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to persist auto-answer flag: ${e.message}")
        }
    }

    private fun readPersistedAutoAnswerFlag(context: Context): Boolean {
        return try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_WAS_AUTO_ANSWERED, false)
        } catch (e: Exception) {
            false
        }
    }

    private fun readPersistedNumber(context: Context): String {
        return try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_PENDING_NUMBER, "") ?: ""
        } catch (e: Exception) {
            ""
        }
    }

    private fun clearPersistedAutoAnswerFlag(context: Context) {
        try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_WAS_AUTO_ANSWERED, false)
                .putString(KEY_PENDING_NUMBER, "")
                .apply()
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to clear auto-answer flag: ${e.message}")
        }
    }

    private fun launchMainActivity(context: Context) {
        try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            launchIntent?.let {
                it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                context.startActivity(it)
                Log.d("PhoneCallService", "Successfully launched MainActivity")
            }
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to launch MainActivity: ${e.message}")
        }
    }

    private fun triggerFlutterCallState(event: String, number: String, recordingPath: String? = null) {
        try {
            val mainActivityClass = Class.forName("com.njtech.allin1.MainActivity")
            val callbackField = mainActivityClass.getField("callStateCallback")
            val callback = callbackField.get(null) as? kotlin.jvm.functions.Function3<String, String, String?, Unit>
            if (callback != null) {
                callback.invoke(event, number, recordingPath)
                Log.d("PhoneCallService", "Successfully triggered Flutter callback via reflection: $event, rec=$recordingPath")
            } else {
                Log.d("PhoneCallService", "Flutter callback is null (MainActivity is not running or disposed)")
            }
        } catch (e: Exception) {
            Log.d("PhoneCallService", "Could not trigger callback via reflection (MainActivity is probably booting): ${e.message}")
        }
    }

    // FIX (Aug 31 2026 — Nizam: "chitti loud speaker on pannama,
    // hearing valiya than kekuthu").
    //
    // ROOT CAUSE: AudioManager.setSpeakerphoneOn was DEPRECATED in API
    // 31 (Android 12) and on many Android 12+ devices it silently does
    // nothing — no exception, no log, the call just stays on the
    // earpiece. MODE_IN_COMMUNICATION routes to the earpiece by
    // default, so the symptom is exactly "I can hear Chitti with the
    // phone at my ear, but the speaker never comes on". The 1s/2s
    // retries below could never have fixed it: re-calling an API the
    // OS is ignoring just gets ignored three times.
    //
    // On API 31+ the supported route is setCommunicationDevice() with
    // the built-in speaker picked out of the available devices list.
    // The legacy path is kept for older phones (the Lenovo K9 class of
    // device), where setSpeakerphoneOn genuinely does work.
    @Suppress("DEPRECATION")
    private fun forceSpeakerRoute(audioManager: AudioManager) {
        try {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        } catch (e: Exception) {
            try {
                audioManager.mode = AudioManager.MODE_IN_CALL
            } catch (_: Exception) {}
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val speaker = audioManager.availableCommunicationDevices
                    .firstOrNull { it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                if (speaker != null) {
                    val ok = audioManager.setCommunicationDevice(speaker)
                    Log.d("PhoneCallService", "setCommunicationDevice(builtin speaker) = $ok")
                }
            } catch (e: Exception) {
                Log.e("PhoneCallService", "setCommunicationDevice failed: ${e.message}")
            }
        }

        try {
            audioManager.isSpeakerphoneOn = true
            Log.d("PhoneCallService", "isSpeakerphoneOn set to true")
        } catch (e: Exception) {
            Log.e("PhoneCallService", "isSpeakerphoneOn failed: ${e.message}")
        }
    }

    // ROOT CAUSE FOUND (Aug 31 2026 — via the diagnostics string added
    // this session): MainActivity.kt calls this via reflection
    // (`method.invoke(null, this)`) because it's a shared file across
    // all 4 flavors and can't hold a compile-time reference to an
    // admin-only object. Kotlin `object` members are NOT static from
    // Java/reflection's point of view unless marked @JvmStatic — without
    // it they're real instance methods on the singleton's generated
    // class, so `invoke(null, ...)` throws NullPointerException("null
    // receiver") and silently falls into MainActivity's AudioManager-
    // only catch-block fallback. This means EVERY speaker-route fix
    // written in this file across every previous round of this bug —
    // forceSpeakerRoute, setCommunicationDevice, and the entire
    // ChittiInCallService/default-dialer work — has never actually run
    // on a real device. Not an OEM/Oppo/Lenovo issue at all.
    @JvmStatic
    fun enableSpeakerphone(context: Context) {
        // NEW (Aug 31 2026 — Option A): the REAL fix, tried first. This
        // only does anything once Chitti holds the Phone role and
        // ChittiInCallService is actually bound to this call — confirmed
        // by testing that the AudioManager path below has zero effect on
        // a real SIM call's route on either Oppo or Lenovo. Kept both:
        // this one is the fix, the AudioManager one below is a harmless
        // no-op fallback for whatever it's worth on devices/paths where
        // the role hasn't been granted yet.
        val routedViaTelecom = ChittiInCallService.instance?.routeToSpeaker() ?: false
        speakerOnViaTelecom = routedViaTelecom
        Log.d("PhoneCallService", "Telecom-level speaker route attempt: $routedViaTelecom")

        try {
            lastSpeakerDiagnostics = buildSpeakerDiagnostics(context, routedViaTelecom)
        } catch (_: Exception) {}

        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            forceSpeakerRoute(audioManager)
            Log.d("PhoneCallService", "Speakerphone routing enabled successfully")

            // Re-force speakerphone after 1s and 2s delays to override OS connection overrides
            val handler = Handler(Looper.getMainLooper())
            handler.postDelayed({
                try {
                    ChittiInCallService.instance?.routeToSpeaker()
                    forceSpeakerRoute(audioManager)
                    Log.d("PhoneCallService", "Speakerphone routing re-forced (1s delay)")
                } catch (e: Exception) {}
            }, 1000)

            handler.postDelayed({
                try {
                    ChittiInCallService.instance?.routeToSpeaker()
                    forceSpeakerRoute(audioManager)
                    Log.d("PhoneCallService", "Speakerphone routing re-forced (2s delay)")
                } catch (e: Exception) {}
            }, 2000)
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to enable speakerphone routing: ${e.message}")
        }
    }

    // ── Telecom call tracking + admin controls (Option A) ──────────────
    //
    // Called by ChittiInCallService.onCallAdded/onCallRemoved. Kept
    // separate from the existing CallReceiver-driven ringing/connected/
    // ended flow above (which still works unchanged for auto-answer and
    // recording) — this is purely additive, giving the admin a manual
    // hang-up/speaker-toggle path now that Android no longer shows its
    // own in-call screen for calls this app is the default Phone app for.
    fun onTelecomCallAdded(context: Context, call: Call) {
        activeTelecomCall = call
        showInCallNotification(context, call)
    }

    fun onTelecomCallRemoved(context: Context, call: Call) {
        if (activeTelecomCall == call) {
            activeTelecomCall = null
        }
        speakerOnViaTelecom = false
        cancelInCallNotification(context)
    }

    fun hangUpActiveCall(context: Context) {
        try {
            activeTelecomCall?.disconnect()
            Log.d("PhoneCallService", "Active call disconnected via notification action.")
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to disconnect active call: ${e.message}")
        }
        cancelInCallNotification(context)
    }

    fun toggleSpeakerOnActiveCall(context: Context) {
        val service = ChittiInCallService.instance ?: return
        if (speakerOnViaTelecom) {
            service.routeToEarpiece()
            speakerOnViaTelecom = false
        } else {
            service.routeToSpeaker()
            speakerOnViaTelecom = true
        }
        activeTelecomCall?.let { showInCallNotification(context, it) }
    }

    // Minimal, notification-based call controls — deliberately not a
    // full custom in-call Activity for this first pass (per Nizam's
    // "own phone la itha pananmudilana" — smaller surface area to get
    // wrong on the phone the business actually runs on). Gives the
    // admin a way to hang up or flip the speaker for any call, whether
    // Chitti auto-answered it or the admin answered/placed it manually.
    private fun showInCallNotification(context: Context, call: Call) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val existing = nm.getNotificationChannel(IN_CALL_NOTIFICATION_CHANNEL_ID)
                if (existing == null) {
                    val channel = NotificationChannel(
                        IN_CALL_NOTIFICATION_CHANNEL_ID,
                        "Chitti Call Controls",
                        NotificationManager.IMPORTANCE_HIGH,
                    ).apply {
                        description = "Hang up / speaker controls while Chitti is handling a call."
                        setShowBadge(false)
                    }
                    nm.createNotificationChannel(channel)
                }
            }

            val hangupIntent = PendingIntent.getBroadcast(
                context, 0,
                Intent(context, ChittiCallNotificationActionReceiver::class.java).setAction(ChittiCallNotificationActionReceiver.ACTION_HANGUP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val speakerIntent = PendingIntent.getBroadcast(
                context, 1,
                Intent(context, ChittiCallNotificationActionReceiver::class.java).setAction(ChittiCallNotificationActionReceiver.ACTION_TOGGLE_SPEAKER),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val number = call.details?.handle?.schemeSpecificPart ?: "Unknown"
            val speakerLabel = if (speakerOnViaTelecom) "Speaker: ON (tap for Earpiece)" else "Speaker: OFF (tap for Speaker)"

            val notification = NotificationCompat.Builder(context, IN_CALL_NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.sym_call_incoming)
                .setContentTitle("Chitti call in progress")
                .setContentText(number)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .addAction(0, speakerLabel, speakerIntent)
                .addAction(0, "Hang Up", hangupIntent)
                .build()

            nm.notify(IN_CALL_NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to show in-call notification: ${e.message}")
        }
    }

    fun cancelInCallNotification(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(IN_CALL_NOTIFICATION_ID)
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to cancel in-call notification: ${e.message}")
        }
    }

    // Same reflection-from-MainActivity path as enableSpeakerphone above
    // — @JvmStatic is required or this silently never runs either.
    @JvmStatic
    fun resetAudioMode(context: Context) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            // Must release the communication device explicitly on API
            // 31+, or the speaker route can stick to every LATER call
            // on this phone — the bug the original reset() was written
            // to prevent, reintroduced if only the legacy flag is
            // cleared.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try {
                    audioManager.clearCommunicationDevice()
                } catch (e: Exception) {
                    Log.e("PhoneCallService", "clearCommunicationDevice failed: ${e.message}")
                }
            }
            audioManager.mode = AudioManager.MODE_NORMAL
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = false
            Log.d("PhoneCallService", "Audio settings reset to normal mode")
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to reset speakerphone: ${e.message}")
        }
    }
}
