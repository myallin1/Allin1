package com.njtech.allin1

import android.content.Intent
import android.speech.RecognitionService

// The <voice-interaction-service> manifest resource requires a
// recognitionService reference to parse at all — this is that
// reference. It is intentionally a no-op: actual speech capture for
// the assist-gesture path happens once Flutter's GuruOverlayService
// panel opens (same mic/STT pipeline every other Chitti surface uses),
// and the future "Hey Chitti" wake-word engine (Picovoice, pending the
// AccessKey/model from Nizam) is a separate always-on listener, not
// this on-demand system RecognitionService. Never actually invoked in
// this app's flow, but must exist and be declared for the assistant
// registration to be valid.
class ChittiRecognitionService : RecognitionService() {
    override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
        listener?.error(android.speech.SpeechRecognizer.ERROR_CLIENT)
    }

    override fun onCancel(listener: Callback?) {}

    override fun onStopListening(listener: Callback?) {}
}
