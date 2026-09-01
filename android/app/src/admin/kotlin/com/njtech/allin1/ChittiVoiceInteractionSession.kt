package com.njtech.allin1

import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.util.Log

// Step 3 (Aug 30 2026 — Nizam: "home screen and lock screen la hey
// chitti nu koopitave chitti wake aganum"). This session has no visible
// UI of its own on purpose — onShow() fires the moment the assistant
// gesture is invoked (including from the lock screen), and this just
// bounces straight to MainActivity with the "assist_wake" extra that
// MainActivity.maybeWakeOverLockScreen() checks before applying the
// show-over-lock-screen flags. That gate is the fix for the
// unconditional-lock-bypass bug found while building this — only THIS
// path, triggered by the deliberate system assist gesture, gets it.
class ChittiVoiceInteractionSession(context: Context) : VoiceInteractionSession(context) {

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        Log.d("ChittiVoiceInteraction", "Assistant invoked (showFlags=$showFlags) — waking Chitti.")

        playWakeChime()

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("assist_wake", true)
            // No spoken command yet — this is the assist-GESTURE path
            // (power button / home swipe), not the "Hey Chitti" wake-word
            // path (blocked on the Picovoice AccessKey/model, see the
            // conversation this was scoped from). MainActivity opens
            // straight into the panel with the mic already listening via
            // GuruOverlayService.show(autoStartMic: true) — see
            // ChittiAccessibilityBridge.onAssistTriggered.
            putExtra("assist_trigger", true)
        }
        try {
            startAssistantActivity(launchIntent)
        } catch (e: Exception) {
            Log.e("ChittiVoiceInteraction", "Failed to start assistant activity: ${e.message}")
        }

        // This session has no content view of its own — MainActivity is
        // the real UI. Hiding immediately avoids a blank system session
        // window sitting behind the activity we just launched.
        hide()
    }

    private fun playWakeChime() {
        try {
            val chimeUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val player = MediaPlayer.create(context, chimeUri) ?: return
            player.setOnCompletionListener { it.release() }
            player.start()
        } catch (e: Exception) {
            Log.e("ChittiVoiceInteraction", "Wake chime failed (non-fatal): ${e.message}")
        }
    }
}
