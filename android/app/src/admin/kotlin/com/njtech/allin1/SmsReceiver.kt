package com.njtech.allin1

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SmsMessage
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_RECENT_SMS = "flutter.chitti_recent_sms_log"
        private const val MAX_LOGGED_SMS = 20

        @JvmStatic
        fun saveSmsLocally(context: Context, sender: String, body: String, timestamp: Long) {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val existingJson = prefs.getString(KEY_RECENT_SMS, "[]") ?: "[]"
                val jsonArray = JSONArray(existingJson)

                val newEntry = JSONObject().apply {
                    put("sender", sender)
                    put("body", body)
                    put("timestamp", timestamp)
                }

                val updatedArray = JSONArray()
                updatedArray.put(newEntry)
                for (i in 0 until jsonArray.length()) {
                    if (updatedArray.length() >= MAX_LOGGED_SMS) break
                    updatedArray.put(jsonArray.getJSONObject(i))
                }

                prefs.edit().putString(KEY_RECENT_SMS, updatedArray.toString()).apply()
                Log.d("SmsReceiver", "Saved SMS from $sender. Total stored: ${updatedArray.length()}")
            } catch (e: Exception) {
                Log.e("SmsReceiver", "Error saving SMS locally: ${e.message}")
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (messages.isNullOrEmpty()) return

            val sender = messages[0].displayOriginatingAddress ?: "Unknown"
            val timestamp = messages[0].timestampMillis
            val bodyBuilder = StringBuilder()
            for (msg in messages) {
                bodyBuilder.append(msg.displayMessageBody)
            }
            val body = bodyBuilder.toString()

            Log.d("SmsReceiver", "Received SMS from: $sender, length: ${body.length}")

            // Persist locally
            saveSmsLocally(context, sender, body, timestamp)

            // Forward to Flutter via MainActivity reflection if alive
            try {
                val mainActivityClass = Class.forName("com.njtech.allin1.MainActivity")
                val callbackField = mainActivityClass.getField("smsReceivedCallback")
                val callback = callbackField.get(null) as? kotlin.jvm.functions.Function2<String, String, Unit>
                callback?.invoke(sender, body)
            } catch (e: Exception) {
                Log.d("SmsReceiver", "MainActivity not attached for live SMS push: ${e.message}")
            }
        }
    }
}
