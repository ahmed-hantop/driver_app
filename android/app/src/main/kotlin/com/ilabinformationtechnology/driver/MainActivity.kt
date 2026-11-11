package com.ilabinformationtechnology.driver

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Allow the in-call screen to appear over the lock screen and wake the
        // device when the app is launched by answering a call from a killed /
        // locked state (the WhatsApp-style behaviour). The native CallKit
        // incoming-call UI already handles the ringing screen; these flags are
        // for the Flutter in-call screen that takes over after "Answer".
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }
}
