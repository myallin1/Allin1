package com.njtech.allin1

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

class CallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
            val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
            val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
            Log.d("CallReceiver", "Phone state changed: $state, number: $number")
            
            if (state == TelephonyManager.EXTRA_STATE_RINGING) {
                PhoneCallService.onCallRinging(context, number)
            } else if (state == TelephonyManager.EXTRA_STATE_OFFHOOK) {
                PhoneCallService.onCallConnected(context)
            } else if (state == TelephonyManager.EXTRA_STATE_IDLE) {
                PhoneCallService.onCallEnded(context)
            }
        }
    }
}
