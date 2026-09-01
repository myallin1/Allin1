package com.njtech.allin1

import android.app.Activity
import android.content.Intent
import android.os.Bundle

// NEW (Sep 2 2026 — Nizam: "dialer ah homescreen shorcut vaiya vachu
// pandrathu than best" — jumping straight to the Dialer without opening
// the full admin app every time). A launcher static shortcut's XML
// intent can't carry a custom extra, so this no-UI trampoline is the
// shortcut's real target: it just re-launches MainActivity with
// "open_dialer" set (same pattern the in-call notification already
// uses for "open_in_call_screen") and finishes immediately.
class AdminDialerShortcutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("open_dialer", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(intent)
        finish()
    }
}
