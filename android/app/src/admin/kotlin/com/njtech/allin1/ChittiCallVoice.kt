package com.njtech.allin1

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale

// NEW (Sep 1 2026 — CTO/Gemini diagnosis, confirmed logically sound):
// ChittiCallScreeningService's TTS greeting plays through flutter_tts,
// which (per flutter_tts's own Android source) hardcodes
// USAGE_ASSISTANCE_NAVIGATION_GUIDANCE and never exposes a way to
// change it — that usage plays through the phone's normal MEDIA output
// (speaker/earpiece), which is exactly the acoustic path Android's own
// Acoustic Echo Cancellation suppresses before it reaches the far end
// (confirmed this session: setAudioRoute(SPEAKER)=true genuinely works,
// yet the caller still hears nothing — AEC on the built-in speaker+mic
// pair is the wall, not a routing bug).
//
// AudioAttributes.USAGE_VOICE_COMMUNICATION is the documented, official
// Android attribute for audio that should be mixed into an active
// voice call's path rather than played as ordinary media — this is
// exactly how "this call may be recorded" announcement features and
// similar call-injected-audio apps work without being a VoIP app
// themselves. flutter_tts can't be configured for it, so this is a
// separate, minimal native TextToSpeech instance used ONLY for the
// call-screening greeting — nothing else in the app is affected.
object ChittiCallVoice {
    private const val TAG = "ChittiCallVoice"

    private var tts: TextToSpeech? = null
    private var ready = false
    private var pendingCallback: ((String) -> Unit)? = null
    private var pendingText: String? = null
    private var pendingLocale: String? = null

    @Volatile
    @JvmField
    var lastEvent: String = "idle"

    // BUG FOUND (Sep 1 2026 — from the debug logs, not guessed): the
    // first version of this file constructed TextToSpeech(context) with
    // NO engine package, so it used whatever system-default TTS engine
    // the phone ships with. The flutter_tts path it replaced had always
    // passed forceGoogleTts: true (see ChittiVoiceService.apply) because
    // the OEM default engine does not carry Tamil voice data. Result:
    // START and DONE fired 255ms apart for a 148-character Tamil
    // sentence (a real utterance takes ~9s, as the old flutter_tts logs
    // show) — i.e. the engine silently produced NO audio at all, which
    // is exactly why neither the admin nor the caller heard anything.
    // setLanguage()'s return code was also being discarded, hiding
    // LANG_MISSING_DATA / LANG_NOT_SUPPORTED completely.
    private const val GOOGLE_TTS_PACKAGE = "com.google.android.tts"

    // NEW (Sep 1 2026 — Nizam: "chitti Pesarattu namma customer ku
    // kekuthu but romba low voice"). The acoustic bridge works, but it
    // is lossy by nature: the headset earbud has to be loud enough for
    // the headset mic beside it to pick the speech up cleanly, and only
    // what the mic hears reaches the caller. KEY_PARAM_VOLUME is
    // already 1.0f, but that is a RELATIVE level within whatever the
    // device's voice-call stream volume happens to be set to — if that
    // stream sits at 40%, Chitti speaks at 40%. Raising the stream to
    // its maximum for the duration of the call is what actually makes
    // the bridge carry a strong signal.
    //
    // The previous level is captured so it can be restored when the
    // call ends (see restoreCallVolume) — leaving the admin's phone
    // permanently pinned at max call volume would be a nasty surprise
    // on their next normal conversation.
    private var savedCallVolume: Int? = null

    @JvmStatic
    fun maximizeCallVolume(context: Context) {
        try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            val current = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
            if (savedCallVolume == null) savedCallVolume = current
            if (current < max) {
                am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, max, 0)
            }
            Log.d(TAG, "Voice-call stream volume $current -> $max (saved $savedCallVolume for restore)")
        } catch (e: Exception) {
            Log.e(TAG, "maximizeCallVolume failed: ${e.message}")
        }
    }

    @JvmStatic
    fun restoreCallVolume(context: Context) {
        val saved = savedCallVolume ?: return
        try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, saved, 0)
            Log.d(TAG, "Voice-call stream volume restored to $saved")
        } catch (e: Exception) {
            Log.e(TAG, "restoreCallVolume failed: ${e.message}")
        } finally {
            savedCallVolume = null
        }
    }

    @JvmStatic
    fun speak(context: Context, text: String, languageTag: String, onEvent: (String) -> Unit) {
        pendingCallback = onEvent
        maximizeCallVolume(context)
        val engine = tts
        if (engine == null) {
            pendingText = text
            pendingLocale = languageTag
            tts = TextToSpeech(context.applicationContext, { status ->
                ready = status == TextToSpeech.SUCCESS
                if (ready) {
                    val t = pendingText
                    val l = pendingLocale
                    if (t != null && l != null) configureAndSpeak(t, l)
                } else {
                    lastEvent = "TTS engine init failed (status=$status)"
                    Log.e(TAG, lastEvent)
                    pendingCallback?.invoke(lastEvent)
                }
            }, GOOGLE_TTS_PACKAGE)
        } else if (ready) {
            configureAndSpeak(text, languageTag)
        } else {
            // Init already in flight from a previous call; queue this
            // one's text/locale so the onInit callback above picks it up.
            pendingText = text
            pendingLocale = languageTag
        }
    }

    private fun configureAndSpeak(text: String, languageTag: String) {
        val engine = tts ?: return
        try {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            engine.setAudioAttributes(attrs)
            Log.d(TAG, "AudioAttributes set to USAGE_VOICE_COMMUNICATION")
        } catch (e: Exception) {
            Log.e(TAG, "setAudioAttributes(VOICE_COMMUNICATION) failed: ${e.message}")
        }
        // Must inspect setLanguage()'s return code — it does NOT throw
        // when a language is missing, it returns LANG_MISSING_DATA (-1)
        // or LANG_NOT_SUPPORTED (-2) and then speaks nothing. Silently
        // discarding this is what made the 255ms "START then DONE with
        // no audio" failure invisible for a whole test round.
        try {
            val langResult = engine.setLanguage(Locale.forLanguageTag(languageTag))
            val langLabel = when (langResult) {
                TextToSpeech.LANG_MISSING_DATA -> "LANG_MISSING_DATA"
                TextToSpeech.LANG_NOT_SUPPORTED -> "LANG_NOT_SUPPORTED"
                TextToSpeech.LANG_AVAILABLE -> "LANG_AVAILABLE"
                TextToSpeech.LANG_COUNTRY_AVAILABLE -> "LANG_COUNTRY_AVAILABLE"
                TextToSpeech.LANG_COUNTRY_VAR_AVAILABLE -> "LANG_COUNTRY_VAR_AVAILABLE"
                else -> "code=$langResult"
            }
            Log.d(TAG, "setLanguage($languageTag) -> $langLabel")

            if (langResult == TextToSpeech.LANG_MISSING_DATA || langResult == TextToSpeech.LANG_NOT_SUPPORTED) {
                // Falling back to English is far better than the silent
                // no-audio failure this replaces — the caller at least
                // hears SOMETHING, and the log says exactly why.
                val fallback = engine.setLanguage(Locale.US)
                lastEvent = "LANG_UNAVAILABLE($languageTag=$langLabel), fell back to en-US (result=$fallback)"
                Log.w(TAG, lastEvent)
                pendingCallback?.invoke(lastEvent)
            } else {
                pendingCallback?.invoke("LANG_OK($languageTag=$langLabel)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "setLanguage($languageTag) failed: ${e.message}")
            pendingCallback?.invoke("setLanguage threw: ${e.message}")
        }

        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                lastEvent = "START"
                pendingCallback?.invoke("START")
            }

            override fun onDone(utteranceId: String?) {
                lastEvent = "DONE"
                pendingCallback?.invoke("DONE")
            }

            @Deprecated("Deprecated in Java, still required to override on older API levels")
            override fun onError(utteranceId: String?) {
                lastEvent = "ERROR"
                pendingCallback?.invoke("ERROR")
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                lastEvent = "ERROR(code=$errorCode)"
                pendingCallback?.invoke(lastEvent)
            }
        })

        // CTO point (Sep 1 2026): setAudioAttributes() above is the
        // modern API, but KEY_PARAM_STREAM is the legacy path many TTS
        // engines still actually honour — and when both are present the
        // engine picks whichever it implements. Passing both costs
        // nothing and removes "maybe the engine ignored the attributes"
        // as a remaining unknown.
        val params = Bundle().apply {
            putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_VOICE_CALL)
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
        }
        val id = "chitti_call_${System.currentTimeMillis()}"
        val speakResult = engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, id)
        lastEvent = "speak() returned $speakResult (stream=STREAM_VOICE_CALL, vol=1.0)"
        Log.d(TAG, lastEvent)
    }

    @JvmStatic
    fun stop() {
        try {
            tts?.stop()
        } catch (_: Exception) {}
    }

    // NEW (Sep 2 2026 — Nizam: "quick greeting ah konjam storng
    // pannuvom... beep kapram customer soldra voice ah record
    // pannanum"). A short voicemail-style beep on the same
    // STREAM_VOICE_CALL the greeting itself plays on, so the caller
    // gets a clear, familiar cue that it's their turn to speak — the
    // same reason voicemail systems use one. Blocks for the tone's
    // duration since callers are expected to speak right after it.
    @JvmStatic
    fun playBeep(durationMs: Int = 400) {
        var toneGen: android.media.ToneGenerator? = null
        try {
            toneGen = android.media.ToneGenerator(AudioManager.STREAM_VOICE_CALL, 90)
            toneGen.startTone(android.media.ToneGenerator.TONE_PROP_BEEP, durationMs)
            Thread.sleep(durationMs.toLong())
        } catch (e: Exception) {
            Log.w(TAG, "playBeep failed: ${e.message}")
        } finally {
            try {
                toneGen?.release()
            } catch (_: Exception) {}
        }
    }
}
