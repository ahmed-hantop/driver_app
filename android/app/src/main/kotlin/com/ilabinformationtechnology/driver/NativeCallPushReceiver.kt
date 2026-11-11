package com.ilabinformationtechnology.driver

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver
import java.io.Serializable
import java.util.HashMap

/**
 * Handles call pushes before Flutter is started.  Android may remove a Flutter
 * task from recents while FCM still delivers the C2DM broadcast; relying on a
 * Dart background isolate at that point is too late for an incoming call.
 */
class NativeCallPushReceiver : FlutterFirebaseMessagingReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "com.google.android.c2dm.intent.RECEIVE" || intent.extras == null) {
            super.onReceive(context, intent)
            return
        }

        // FCM data values are copied to the C2DM intent extras. Reading the
        // bundle directly avoids starting Flutter or depending on its plugin.
        val data = intent.extras!!
        if (data.getString("type") != "call_invite") {
            super.onReceive(context, intent)
            return
        }

        val callId = data.getString("call_log_id")?.toLongOrNull()
        if (callId == null) {
            super.onReceive(context, intent)
            return
        }
        val bundle = buildCallkitBundle(callId, data)
        val callIntent = Intent().apply {
            setClassName(context.packageName, CALLKIT_RECEIVER)
            action = "${context.packageName}.$ACTION_INCOMING"
            putExtra(EXTRA_INCOMING_DATA, bundle)
            `package` = context.packageName
        }

        try {
            context.sendBroadcast(callIntent)
            Log.i(TAG, "Native incoming call dispatched id=$callId")
        } catch (error: Exception) {
            Log.e(TAG, "Native incoming call dispatch failed", error)
        }

        // The native CallKit UI is the immediate delivery path. Delegate to
        // Firebase Messaging too, so normal Flutter background-state handling
        // continues for the same push.
        super.onReceive(context, intent)
    }

    private fun buildCallkitBundle(callId: Long, data: Bundle): Bundle = Bundle().apply {
        putString("EXTRA_CALLKIT_ID", uuidForCall(callId))
        putString("EXTRA_CALLKIT_NAME_CALLER", data.getString("caller_name") ?: "Admin")
        putString("EXTRA_CALLKIT_APP_NAME", "Speed Driver")
        putString("EXTRA_CALLKIT_HANDLE", "Speed Logistics")
        putString("EXTRA_CALLKIT_AVATAR", "")
        putInt("EXTRA_CALLKIT_TYPE", if (data.getString("call_type") == "video") 1 else 0)
        putLong("EXTRA_CALLKIT_DURATION", 60_000L)
        putString("EXTRA_CALLKIT_TEXT_ACCEPT", "Answer")
        putString("EXTRA_CALLKIT_TEXT_DECLINE", "Decline")
        putSerializable("EXTRA_CALLKIT_EXTRA", HashMap<String, Any?>().apply {
            put("call_log_id", callId.toString())
            put("caller_name", data.getString("caller_name") ?: "Admin")
            put("call_type", data.getString("call_type") ?: "voice")
        } as Serializable)
        putSerializable("EXTRA_CALLKIT_HEADERS", HashMap<String, Any?>() as Serializable)
        putBoolean("EXTRA_CALLKIT_IS_CUSTOM_NOTIFICATION", true)
        putBoolean("EXTRA_CALLKIT_IS_CUSTOM_SMALL_EX_NOTIFICATION", false)
        putBoolean("EXTRA_CALLKIT_IS_SHOW_LOGO", false)
        putString("EXTRA_CALLKIT_LOGO_URL", "")
        putBoolean("EXTRA_CALLKIT_IS_SHOW_CALL_ID", false)
        putString("EXTRA_CALLKIT_RINGTONE_PATH", "system_ringtone_default")
        putString("EXTRA_CALLKIT_BACKGROUND_COLOR", "#1A237E")
        putString("EXTRA_CALLKIT_BACKGROUND_URL", "")
        putString("EXTRA_CALLKIT_ACTION_COLOR", "#4CAF50")
        putString("EXTRA_CALLKIT_TEXT_COLOR", "#ffffff")
        putString("EXTRA_CALLKIT_INCOMING_CALL_NOTIFICATION_CHANNEL_NAME", "Incoming Calls")
        putString("EXTRA_CALLKIT_MISSED_CALL_NOTIFICATION_CHANNEL_NAME", "Missed Calls")
        putBoolean("EXTRA_CALLKIT_IS_SHOW_FULL_LOCKED_SCREEN", true)
        putBoolean("EXTRA_CALLKIT_IS_IMPORTANT", true)
        putBoolean("EXTRA_CALLKIT_IS_BOT", false)
        putBoolean("EXTRA_CALLKIT_IS_FULL_SCREEN", false)
        putString("EXTRA_CALLKIT_ACTION_FROM", "fcm_native")
        putBoolean("EXTRA_CALLKIT_MISSED_CALL_SHOW", true)
        putInt("EXTRA_CALLKIT_MISSED_CALL_COUNT", 1)
        putString("EXTRA_CALLKIT_MISSED_CALL_SUBTITLE", "Missed call")
        putBoolean("EXTRA_CALLKIT_MISSED_CALL_CALLBACK_SHOW", false)
        putString("EXTRA_CALLKIT_MISSED_CALL_CALLBACK_TEXT", "")
        putString("EXTRA_CALLKIT_CALLING_ID", "")
        putBoolean("EXTRA_CALLKIT_CALLING_SHOW", true)
        putString("EXTRA_CALLKIT_CALLING_SUBTITLE", "")
        putBoolean("EXTRA_CALLKIT_CALLING_HANG_UP_SHOW", true)
        putString("EXTRA_CALLKIT_CALLING_HANG_UP_TEXT", "")
    }

    private fun uuidForCall(callId: Long): String =
        "00000000-0000-4000-8000-${callId.toString(16).padStart(12, '0').takeLast(12)}"

    private companion object {
        const val TAG = "NativeCallPush"
        const val ACTION_INCOMING = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_INCOMING"
        const val EXTRA_INCOMING_DATA = "EXTRA_CALLKIT_INCOMING_DATA"
        const val CALLKIT_RECEIVER = "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver"
    }
}
