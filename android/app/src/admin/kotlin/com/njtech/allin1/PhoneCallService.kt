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
    private fun buildSpeakerDiagnostics(context: Context, routedViaTelecom: Boolean, routeLabel: String): String {
        val isDefaultDialer = try {
            val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            tm.defaultDialerPackage == context.packageName
        } catch (e: Exception) {
            false
        }
        val serviceBound = ChittiInCallService.instance != null
        val hasTelecomCall = activeTelecomCall != null
        // audioMode is reported because setting it to
        // MODE_IN_COMMUNICATION (3) during a real cellular call is what
        // was silently killing the uplink — see forceSpeakerRoute's
        // header. On a healthy screened call this should now read 2
        // (MODE_IN_CALL), set by Telecom, not by this app.
        val audioMode = try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (am.mode) {
                AudioManager.MODE_NORMAL -> "NORMAL(0)"
                AudioManager.MODE_IN_CALL -> "IN_CALL(2)"
                AudioManager.MODE_IN_COMMUNICATION -> "IN_COMMUNICATION(3)"
                else -> "mode=${am.mode}"
            }
        } catch (e: Exception) {
            "unknown"
        }
        return "isDefaultDialer=$isDefaultDialer, inCallServiceBound=$serviceBound, " +
            "hasLiveTelecomCall=$hasTelecomCall, setAudioRoute($routeLabel)=$routedViaTelecom, " +
            "audioMode=$audioMode"
    }
    private var isRinging = false
    private var incomingNumber = ""
    private val handler = Handler(Looper.getMainLooper())
    private var answerRunnable: Runnable? = null

    private var wasAutoAnswered = false

    private var mediaRecorder: MediaRecorder? = null

    // Wall-clock time the current call became active, so the in-call
    // screen can render a running duration. Null between calls.
    @Volatile
    private var callConnectedAtMillis: Long? = null
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

            // Start native call recording (now after the route is set).
            // NEW (Sep 1 2026 — mic-isolation lever): MediaRecorder with
            // AudioSource.MIC takes an exclusive hold on the microphone
            // on many devices. While diagnosing "the caller hears
            // nothing", that makes it a second suspect alongside the
            // audio-mode bug fixed in forceSpeakerRoute — so it can now
            // be switched off from Admin AI Settings to isolate the two
            // instead of guessing which one matters.
            val prefs = try {
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            } catch (e: Exception) {
                null
            }
            val recordingEnabled = try {
                prefs?.getBoolean("flutter.kChittiCallRecordingEnabled", true) ?: true
            } catch (e: Exception) {
                true
            }
            // ROOT-CAUSE FIX (Sep 1 2026 — Nizam: "customer pesurathu and
            // avanga yena sollavaranganu chitti ku therila").
            //
            // MediaRecorder(AudioSource.MIC) and SpeechRecognizer cannot
            // both hold the microphone: whichever grabs it first wins and
            // the other gets silence. Recording starts here, at call
            // connect — seconds before the conversation loop asks to
            // listen — so in full-conversation mode the recorder was
            // always winning and STT was guaranteed to return
            // error_speech_timeout. That is exactly the repeating error
            // in the logs, on every single screened call.
            //
            // The two modes want opposite things, so they now get them:
            //   full         -> STT owns the mic (no recorder)
            //   quick_record -> recorder owns the mic (no STT anyway)
            val answeringMode = try {
                prefs?.getString("flutter.kChittiCallAnsweringMode", "quick_record") ?: "quick_record"
            } catch (e: Exception) {
                "quick_record"
            }
            val fullConversationMode = answeringMode == "full"

            when {
                fullConversationMode -> Log.d("PhoneCallService", "Full-conversation mode — " +
                    "NOT starting the recorder so SpeechRecognizer can hold the microphone.")
                recordingEnabled -> startRecording(context, number)
                else -> Log.d("PhoneCallService", "Call recording DISABLED by setting — " +
                    "leaving the microphone free for the cellular uplink.")
            }

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
            // FIX (Sep 2 2026 — Nizam: "oppo la o dialer and samsung
            // dialersla call record pannuna sound varathu, namma record
            // um athe system ah maathu"). Stock dialers are privileged
            // system apps that read both sides of the call directly
            // (AudioSource.VOICE_CALL); a third-party app recording via
            // the plain microphone during a live call is exactly the
            // case several Android telephony stacks inject an audible
            // "this call is being recorded" tone for. VOICE_CALL isn't
            // guaranteed available to a non-system app on every OEM —
            // where it's blocked, MediaRecorder throws at setAudioSource
            // or prepare(), so this falls back to MIC rather than fail
            // recording outright.
            var usedVoiceCallSource = false
            try {
                recorder.setAudioSource(MediaRecorder.AudioSource.VOICE_CALL)
                usedVoiceCallSource = true
            } catch (e: Exception) {
                Log.w("PhoneCallService", "VOICE_CALL audio source unavailable, falling back to MIC: ${e.message}")
                recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            }
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioEncodingBitRate(64000)
            recorder.setAudioSamplingRate(44100)
            recorder.setOutputFile(file.absolutePath)
            try {
                recorder.prepare()
                recorder.start()
            } catch (e: Exception) {
                if (usedVoiceCallSource) {
                    Log.w("PhoneCallService", "VOICE_CALL source rejected at prepare/start, retrying with MIC: ${e.message}")
                    recorder.reset()
                    recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
                    recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                    recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    recorder.setAudioEncodingBitRate(64000)
                    recorder.setAudioSamplingRate(44100)
                    recorder.setOutputFile(file.absolutePath)
                    recorder.prepare()
                    recorder.start()
                } else {
                    throw e
                }
            }
            // BUG FIX (Sep 1 2026): the started recorder was never stored
            // in `mediaRecorder`, so stopRecording()'s `mediaRecorder?.`
            // was always null — stop()/release() never ran and the .m4a
            // was left un-finalized (and the mic held) until the process
            // happened to tear it down. Without this line the whole
            // stop/toggle path below is dead code.
            mediaRecorder = recorder
            Log.d("PhoneCallService", "Call recording started at: ${file.absolutePath}")
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to start call recording: ${e.message}")
            mediaRecorder = null
            currentRecordingPath = null
        }
    }

    // NEW (Sep 1 2026 — Nizam: "anga venumna call record pandra option
    // vachuklam... antha screeen la call recording on,off option").
    // Lets the in-call screen start/stop recording mid-call instead of
    // the decision being fixed at call-connect time.
    @JvmStatic
    fun isRecordingActive(): Boolean = mediaRecorder != null

    @JvmStatic
    fun setRecordingActive(context: Context, enabled: Boolean): Boolean {
        return try {
            if (enabled) {
                if (mediaRecorder != null) return true
                val number = activeTelecomCall?.details?.handle?.schemeSpecificPart
                    ?: incomingNumber
                startRecording(context, number)
                mediaRecorder != null
            } else {
                if (mediaRecorder == null) return false
                stopRecording(context)
                false
            }
        } catch (e: Exception) {
            Log.e("PhoneCallService", "setRecordingActive($enabled) failed: ${e.message}")
            mediaRecorder != null
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
    // FIX (Sep 1 2026 — wired-headset loopback experiment): this used
    // to unconditionally hunt for TYPE_BUILTIN_SPEAKER and force
    // isSpeakerphoneOn=true — which would silently override a plugged-
    // in headset back to the phone's own speaker, defeating the cable
    // test even with correct wiring. Now honors the same
    // "flutter.kChittiPreferWiredHeadsetRoute" toggle
    // enableSpeakerphone() reads for the real Telecom route above, so
    // this AudioManager-level fallback path picks the same device.
    // ROOT-CAUSE FIX (Sep 1 2026 — Nizam: "mic line on agave ila pola
    // Athan customer ku onnume kekkala"). That observation was right,
    // and this line was the cause.
    //
    // MODE_IN_COMMUNICATION is the mode for VOIP audio a third-party
    // app owns (WhatsApp/Meet style). Setting it during a REAL cellular
    // call tells the audio policy manager that an app has taken over
    // the voice path — which tears down the telephony uplink route the
    // caller's audio actually travels on. That is exactly the reported
    // symptom across all three route tests (speaker, Bluetooth, wired):
    // Chitti is audible locally every time, and the caller hears
    // nothing on any of them. It was never an echo-cancellation wall on
    // three different audio paths; it was this app switching the phone
    // out of cellular-call mode on every one of them.
    //
    // The correct mode for a live cellular call is MODE_IN_CALL, and
    // when this app is the default dialer, Telecom already sets and
    // owns it — so the right move is to not touch `mode` at all while a
    // Telecom call is live, and let setAudioRoute() (the supported API
    // for exactly this) do the routing on its own.
    @Suppress("DEPRECATION")
    private fun forceSpeakerRoute(audioManager: AudioManager, preferHeadset: Boolean = false) {
        val telecomCallLive = activeTelecomCall != null && ChittiInCallService.instance != null
        if (telecomCallLive) {
            Log.d("PhoneCallService", "Live Telecom call — NOT touching audioManager.mode " +
                "(currently ${audioManager.mode}); Telecom owns it. Routing via setAudioRoute only.")
        } else {
            // No Telecom call (e.g. the role isn't granted): fall back
            // to the legacy path, but prefer MODE_IN_CALL over
            // MODE_IN_COMMUNICATION for the same reason as above.
            try {
                audioManager.mode = AudioManager.MODE_IN_CALL
            } catch (e: Exception) {
                try {
                    audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                } catch (_: Exception) {}
            }
        }

        if (!telecomCallLive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val devices = audioManager.availableCommunicationDevices
                val externalDevice = devices.firstOrNull {
                    it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                        it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                        it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                }
                val target = if (preferHeadset && externalDevice != null) {
                    externalDevice
                } else {
                    devices.firstOrNull { it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                }
                if (target != null) {
                    val ok = audioManager.setCommunicationDevice(target)
                    Log.d("PhoneCallService", "setCommunicationDevice(type=${target.type}) = $ok")
                }
            } catch (e: Exception) {
                Log.e("PhoneCallService", "setCommunicationDevice failed: ${e.message}")
            }
        }

        // Also skipped while Telecom owns the call: this is the same
        // deprecated VoIP-era API as `mode` above, and forcing it
        // against a live Telecom call fights setAudioRoute() rather
        // than helping it. (When there is no Telecom call it still
        // matters, and must stay false when a headset route is wanted
        // or this line alone undoes everything above it.)
        if (telecomCallLive) return
        try {
            audioManager.isSpeakerphoneOn = !preferHeadset
            Log.d("PhoneCallService", "isSpeakerphoneOn set to ${!preferHeadset}")
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
        // NEW (Sep 1 2026 — Nizam: "headphone jack la namma technical
        // plan panni athukapram ithe idea va implement pannalam").
        // Confirmed working: setAudioRoute(SPEAKER)=true really routes
        // the real call now (Option A). The NEW problem discovered is
        // Android's own Acoustic Echo Cancellation on the built-in
        // speaker+mic pair silently killing the acoustic loop this
        // whole feature depends on — a wired-headset loopback cable
        // (audio-out wired to mic-in) is being tried as a path AEC may
        // not scrub as aggressively. Reads a toggle from Admin AI
        // Settings so the admin controls which route Chitti tries,
        // instead of this always forcing BUILTIN_SPEAKER regardless of
        // whether a headset is plugged in (which would have silently
        // defeated the cable test even if wired correctly).
        // UPDATED (Sep 1 2026 — CTO's Bluetooth acoustic-bridge idea):
        // widened from a wired-only boolean to a three-way route choice
        // ("speaker" | "wired" | "bluetooth"), because the neckband test
        // hits the exact same trap the cable test did — with the call
        // pinned to ROUTE_SPEAKER, pairing a headset changes nothing and
        // the experiment fails for the wrong reason. Falls back to the
        // speaker whenever the requested route isn't actually available,
        // and the chosen route is recorded in the diagnostics line so
        // the debug log always says which one was really used.
        val prefs = try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        } catch (e: Exception) {
            null
        }
        var requestedRoute = try {
            prefs?.getString("flutter.kChittiCallAudioRoute", "speaker") ?: "speaker"
        } catch (e: Exception) {
            "speaker"
        }
        // Back-compat with the earlier boolean-only wired-headset flag,
        // so an admin who had it switched on doesn't silently lose it.
        if (requestedRoute == "speaker") {
            val legacyWired = try {
                prefs?.getBoolean("flutter.kChittiPreferWiredHeadsetRoute", false) ?: false
            } catch (e: Exception) {
                false
            }
            if (legacyWired) requestedRoute = "wired"
        }

        val service = ChittiInCallService.instance
        val wiredOk = requestedRoute == "wired" && (service?.isWiredHeadsetRouteAvailable() ?: false)
        val btOk = requestedRoute == "bluetooth" && (service?.isBluetoothRouteAvailable() ?: false)

        val routedViaTelecom = when {
            wiredOk -> service?.routeToWiredHeadset() ?: false
            btOk -> service?.routeToBluetooth() ?: false
            else -> service?.routeToSpeaker() ?: false
        }
        val actualRoute = when {
            wiredOk -> "WIRED_HEADSET"
            btOk -> "BLUETOOTH"
            else -> "SPEAKER"
        }
        // Not the same as requestedRoute: says so explicitly when the
        // requested device simply wasn't connected, which is the single
        // most likely reason one of these experiments "doesn't work".
        val routeNote = if (requestedRoute != actualRoute.lowercase().replace("_headset", "")
            .replace("wired_headset", "wired")) {
            " (requested=$requestedRoute, not available — used $actualRoute)"
        } else {
            ""
        }
        // True when Telecom actually accepted the route — used below to
        // skip the legacy re-force timers that would otherwise cut
        // speech a second in.
        val telecomRouteHeld = routedViaTelecom && service != null
        speakerOnViaTelecom = routedViaTelecom
        Log.d("PhoneCallService", "Telecom route attempt -> $actualRoute$routeNote: $routedViaTelecom")

        try {
            lastSpeakerDiagnostics =
                buildSpeakerDiagnostics(context, routedViaTelecom, actualRoute) + routeNote
        } catch (_: Exception) {}

        val headsetAvailable = wiredOk || btOk

        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            forceSpeakerRoute(audioManager, headsetAvailable)
            Log.d("PhoneCallService", "Audio routing enabled successfully (headset=$headsetAvailable)")

            // ROOT-CAUSE FIX (Sep 1 2026 — Nizam: "wired headphones la
            // vanakkam mattum kettuchu athukapram... full continuous ah
            // customer ku anupala").
            //
            // These 1s and 2s re-forces were written back when NO route
            // call worked at all, as a blind "try again in case the OS
            // overrode us" defence. Now that setAudioRoute() genuinely
            // works (logs show it true, with audioMode=IN_CALL(2)), they
            // are actively harmful: each one TEARS DOWN AND REBUILDS the
            // audio path — one second into Chitti's greeting, which is
            // exactly one word in. That is the reported symptom, and it
            // explains why it reproduced identically on wired AND
            // Bluetooth: the interruption is ours, not the accessory's.
            //
            // With a live Telecom call the route is set once and left
            // alone. The retries are kept only for the no-Telecom-call
            // fallback path, where nothing is speaking yet anyway.
            if (telecomRouteHeld) {
                Log.d("PhoneCallService", "Telecom route set once — skipping the 1s/2s " +
                    "re-forces so they cannot interrupt speech mid-sentence.")
                return
            }

            val handler = Handler(Looper.getMainLooper())
            handler.postDelayed({
                try {
                    forceSpeakerRoute(audioManager, headsetAvailable)
                    Log.d("PhoneCallService", "Audio routing re-forced (1s delay, no Telecom call)")
                } catch (e: Exception) {}
            }, 1000)

            handler.postDelayed({
                try {
                    forceSpeakerRoute(audioManager, headsetAvailable)
                    Log.d("PhoneCallService", "Audio routing re-forced (2s delay, no Telecom call)")
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
        callConnectedAtMillis = System.currentTimeMillis()
        showInCallNotification(context, call)
    }

    fun onTelecomCallRemoved(context: Context, call: Call) {
        if (activeTelecomCall == call) {
            activeTelecomCall = null
        }
        speakerOnViaTelecom = false
        callConnectedAtMillis = null
        cancelInCallNotification(context)
    }

    // NEW (Sep 1 2026 — minimal dialer). Reports the live Telecom call
    // so the in-app dialer can show "call in progress" and offer hang
    // up / speaker. Returns null when there is no call, which the UI
    // uses to hide the card entirely.
    @JvmStatic
    fun activeCallInfo(): Map<String, Any?>? {
        val call = activeTelecomCall ?: return null
        return try {
            val number = call.details?.handle?.schemeSpecificPart
            val stateLabel = when (call.state) {
                Call.STATE_RINGING -> "ringing"
                Call.STATE_DIALING -> "dialing"
                Call.STATE_ACTIVE -> "active"
                Call.STATE_HOLDING -> "on hold"
                Call.STATE_CONNECTING -> "connecting"
                Call.STATE_DISCONNECTED -> "ended"
                else -> "active"
            }
            mapOf(
                "number" to number,
                "state" to stateLabel,
                "speakerOn" to speakerOnViaTelecom,
                "recording" to (mediaRecorder != null),
                // Lets the in-call screen show a live duration without
                // having to guess when the call actually connected.
                "connectedAt" to callConnectedAtMillis,
            )
        } catch (e: Exception) {
            null
        }
    }

    @JvmStatic
    fun hangUpActiveCall(context: Context) {
        try {
            activeTelecomCall?.disconnect()
            Log.d("PhoneCallService", "Active call disconnected via notification action.")
        } catch (e: Exception) {
            Log.e("PhoneCallService", "Failed to disconnect active call: ${e.message}")
        }
        cancelInCallNotification(context)
    }

    @JvmStatic
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

            // NEW (Sep 1 2026 — Nizam: "notification... atha thottu ulla
            // pona curren calling screene ila"). Tapping the
            // notification now opens the real in-call screen, carrying
            // the extra MainActivity forwards to Flutter so it routes
            // straight there instead of the app's home screen.
            val openIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra("open_in_call_screen", true)
                }
            val contentIntent = if (openIntent != null) {
                PendingIntent.getActivity(
                    context, 2, openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            } else {
                null
            }

            val notification = NotificationCompat.Builder(context, IN_CALL_NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.sym_call_incoming)
                .setContentTitle("Chitti call in progress")
                .setContentText(number)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .apply { if (contentIntent != null) setContentIntent(contentIntent) }
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
        // Put the voice-call stream volume back where the admin had it —
        // ChittiCallVoice raises it to maximum so the acoustic bridge
        // carries a strong enough signal, and leaving it pinned there
        // would ambush the next ordinary call.
        try {
            ChittiCallVoice.restoreCallVolume(context)
        } catch (e: Exception) {
            Log.e("PhoneCallService", "restoreCallVolume failed: ${e.message}")
        }
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
