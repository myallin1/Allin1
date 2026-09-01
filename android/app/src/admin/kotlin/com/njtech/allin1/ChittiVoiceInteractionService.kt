package com.njtech.allin1

import android.service.voice.VoiceInteractionService
import android.util.Log

// Step 1 (Aug 30 2026 — Nizam: default Digital Assistant registration).
// Deliberately thin: VoiceInteractionService itself is just the
// system-facing "this package offers an assistant" registration — all
// the real work (waking the screen, launching the panel) happens in
// ChittiVoiceInteractionSession, which the system creates through
// ChittiVoiceInteractionSessionService below. Admin-only (this file
// lives in src/admin), so this never ships in the customer/hero/seller
// flavors bound for Play Store.
class ChittiVoiceInteractionService : VoiceInteractionService() {
    override fun onReady() {
        super.onReady()
        Log.d("ChittiVoiceInteraction", "Chitti registered as ready for assistant duties.")
    }
}
