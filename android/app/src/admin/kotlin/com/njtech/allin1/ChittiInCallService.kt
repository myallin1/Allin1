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

    // NEW (Sep 1 2026 — Nizam: "headphone jack la namma technical plan
    // panni athukapram ithe idea va implement pannalam"). Confirmed via
    // this session's own testing that the speaker route DOES work now
    // (setAudioRoute(SPEAKER)=true) but the caller still can't hear
    // Chitti — Android's Acoustic Echo Cancellation on the built-in
    // speaker+mic pair is suppressing the acoustic loop the whole
    // scheme depends on. A wired headset's electrical loopback cable
    // (audio-out wired straight into mic-in) is being tried instead —
    // this method is what actually routes the LIVE call to that
    // headset once it's plugged in, which forceSpeakerRoute() never
    // did (it always forced BUILTIN_SPEAKER, which would have silently
    // defeated this test even with the cable correctly wired).
    fun routeToWiredHeadset(): Boolean {
        return try {
            setAudioRoute(CallAudioState.ROUTE_WIRED_HEADSET)
            Log.d(TAG, "setAudioRoute(ROUTE_WIRED_HEADSET) called on the real Telecom call.")
            true
        } catch (e: Exception) {
            Log.e(TAG, "setAudioRoute(ROUTE_WIRED_HEADSET) failed: ${e.message}")
            false
        }
    }

    /** True only once Android reports a wired headset is actually plugged in and usable as a call route. */
    fun isWiredHeadsetRouteAvailable(): Boolean {
        return try {
            val mask = callAudioState?.supportedRouteMask ?: 0
            (mask and CallAudioState.ROUTE_WIRED_HEADSET) != 0
        } catch (e: Exception) {
            false
        }
    }

    // NEW (Sep 1 2026 — CTO's Bluetooth acoustic-bridge proposal). Same
    // reasoning as routeToWiredHeadset above, and the same trap: with
    // the call forced to ROUTE_SPEAKER, pairing a neckband changes
    // nothing — Chitti's voice keeps coming out of the phone's own
    // speaker and the bridge test fails for the wrong reason. This is
    // the more promising of the two loopback paths, because the phone's
    // AEC is calibrated for its OWN speaker/mic geometry and is
    // typically not applied to the Bluetooth SCO path at all (the
    // headset is expected to do its own). Note that a neckband with
    // ENC/ANC on its mic may cancel the loop itself — a plain, cheap
    // headset without noise cancellation is the right thing to test.
    fun routeToBluetooth(): Boolean {
        return try {
            setAudioRoute(CallAudioState.ROUTE_BLUETOOTH)
            Log.d(TAG, "setAudioRoute(ROUTE_BLUETOOTH) called on the real Telecom call.")
            true
        } catch (e: Exception) {
            Log.e(TAG, "setAudioRoute(ROUTE_BLUETOOTH) failed: ${e.message}")
            false
        }
    }

    fun isBluetoothRouteAvailable(): Boolean {
        return try {
            val mask = callAudioState?.supportedRouteMask ?: 0
            (mask and CallAudioState.ROUTE_BLUETOOTH) != 0
        } catch (e: Exception) {
            false
        }
    }
}
