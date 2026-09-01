package com.njtech.allin1

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// NEW (Aug 31 2026 — Option A / default-dialer role): once Chitti holds
// the Phone role, the OS no longer shows its own in-call screen for
// this app's calls — the admin needs SOME way to hang up or toggle the
// speaker manually (e.g. for a call Chitti did NOT auto-answer, or one
// the admin wants to end early). Building a full custom in-call Activity
// was deliberately skipped for this first pass (bigger surface, more
// that could go wrong on a phone this business depends on) — a
// notification with two action buttons covers the actual need with far
// less risk. See PhoneCallService.showInCallNotification().
class ChittiCallNotificationActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_HANGUP = "com.njtech.allin1.action.CALL_HANGUP"
        const val ACTION_TOGGLE_SPEAKER = "com.njtech.allin1.action.CALL_TOGGLE_SPEAKER"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_HANGUP -> PhoneCallService.hangUpActiveCall(context)
            ACTION_TOGGLE_SPEAKER -> PhoneCallService.toggleSpeakerOnActiveCall(context)
        }
    }
}
