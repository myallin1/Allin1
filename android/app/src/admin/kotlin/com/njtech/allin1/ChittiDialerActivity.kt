package com.njtech.allin1

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.telecom.TelecomManager
import android.util.Log

// NEW (Aug 31 2026 — Option A: default-dialer role for real speaker
// control, see ChittiInCallService's header for the full reasoning).
// Android requires the default-dialer app to be able to handle
// ACTION_DIAL / ACTION_CALL / ACTION_VIEW(tel:) — i.e. "the admin
// tapped a phone number in Contacts/Recents" — or normal outgoing
// calling from elsewhere on the phone would silently do nothing once
// Chitti holds the Phone role. This activity is NOT a real dialer UI —
// it has no screen of its own; it just relays the number straight to
// TelecomManager.placeCall() (the same system call the stock dialer
// itself would make) and finishes immediately, so tapping a contact
// keeps working exactly as before. The actual live-call handling
// still happens the normal way in ChittiInCallService.
class ChittiDialerActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri: Uri? = intent?.data
        if (uri != null) {
            try {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                telecomManager.placeCall(uri, null)
            } catch (e: Exception) {
                Log.e("ChittiDialerActivity", "placeCall failed: ${e.message}")
                // Fall back to the system's own dial intent so the tap
                // isn't a dead end even if placeCall() is refused.
                try {
                    val fallback = Intent(Intent.ACTION_CALL, uri)
                    fallback.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(fallback)
                } catch (e2: Exception) {
                    Log.e("ChittiDialerActivity", "Fallback ACTION_CALL also failed: ${e2.message}")
                }
            }
        }
        finish()
    }
}
