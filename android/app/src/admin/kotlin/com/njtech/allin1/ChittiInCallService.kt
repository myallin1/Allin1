package com.njtech.allin1

import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.util.Log

// NEW (per Nizam's request, Aug 31 2026 — "namma than playstore ku
// poga vendammu full plan panitom apram nammaloda own phone la itha
// pananmudilana"): the real, permanent fix for "Chitti loud speaker on
// agala" (confirmed on BOTH Oppo Reno7 Pro and Lenovo K9 — a universal
// Android limitation, not one OEM's bug).
//
// ROOT CAUSE (confirmed by testing, not guessed): AudioManager.setMode/
// setCommunicationDevice/isSpeakerphoneOn (see PhoneCallService.
// forceSpeakerRoute) can only influence audio routing for VoIP-style
// audio a THIRD-PARTY APP owns. A real SIM/VoLTE phone call's audio
// route is owned by Android's Telecom framework — only the app holding
// the device's "Phone" role (RoleManager.ROLE_DIALER) and registered as
// an InCallService is allowed to call setAudioRoute() on that call.
// Every AudioManager call this app made before was accepted (no
// exception) but silently had zero effect on the real call route,
// which is exactly the symptom reported: no error, no crash, just
// permanent silence to the caller.
//
// This service does nothing on its own except exist and register —
// requesting the actual ROLE_DIALER role (see MainActivity's
// "requestDefaultDialerRole") is what makes Android start binding it
// for real calls. Once bound, onCallAdded gives us the live Call
// object; PhoneCallService keeps a reference to THIS SERVICE INSTANCE
// (not the Call) because setAudioRoute() is a method on InCallService
// itself, not on Call.
class ChittiInCallService : InCallService() {

    companion object {
        private const val TAG = "ChittiInCallService"

        @Volatile
        @JvmStatic
        var instance: ChittiInCallService? = null
            private set
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "ChittiInCallService created and bound by Telecom.")
    }

    override fun onDestroy() {
        instance = null
        Log.d(TAG, "ChittiInCallService destroyed/unbound.")
        super.onDestroy()
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        Log.d(TAG, "onCallAdded: state=${call.state}")
        PhoneCallService.onTelecomCallAdded(this, call)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        Log.d(TAG, "onCallRemoved")
        PhoneCallService.onTelecomCallRemoved(this, call)
    }

    /** The one API call this whole feature exists to make. */
    fun routeToSpeaker(): Boolean {
        return try {
            setAudioRoute(CallAudioState.ROUTE_SPEAKER)
            Log.d(TAG, "setAudioRoute(ROUTE_SPEAKER) called on the real Telecom call.")
            true
        } catch (e: Exception) {
            Log.e(TAG, "setAudioRoute(ROUTE_SPEAKER) failed: ${e.message}")
            false
        }
    }

    fun routeToEarpiece(): Boolean {
        return try {
            setAudioRoute(CallAudioState.ROUTE_EARPIECE)
            true
        } catch (e: Exception) {
            Log.e(TAG, "setAudioRoute(ROUTE_EARPIECE) failed: ${e.message}")
            false
        }
    }
}
