package com.hari.otpbridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restart the command link after a reboot so reject-from-Mac keeps working. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (PairingStore(context).isPaired) {
            runCatching { CommandService.start(context) }
        }
    }
}
