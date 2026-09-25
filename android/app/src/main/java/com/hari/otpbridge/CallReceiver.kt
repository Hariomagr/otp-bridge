package com.hari.otpbridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import java.util.UUID

/**
 * Tracks call state transitions (answered / missed / ended). The incoming
 * announcement — with the caller number — is normally made by CallScreener at
 * ring time; this receiver only announces "incoming" as a fallback when the
 * screening role isn't held.
 */
class CallReceiver : BroadcastReceiver() {

    companion object {
        private var lastState = TelephonyManager.CALL_STATE_IDLE
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        if (!PairingStore(context).isPaired) return

        CallForwarder.updateNumber(intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER))

        val state = when (intent.getStringExtra(TelephonyManager.EXTRA_STATE)) {
            TelephonyManager.EXTRA_STATE_RINGING -> TelephonyManager.CALL_STATE_RINGING
            TelephonyManager.EXTRA_STATE_OFFHOOK -> TelephonyManager.CALL_STATE_OFFHOOK
            else -> TelephonyManager.CALL_STATE_IDLE
        }

        when {
            state == TelephonyManager.CALL_STATE_RINGING &&
                lastState != TelephonyManager.CALL_STATE_RINGING -> {
                // Fallback only: if the screener already announced (role held), skip.
                if (!CallForwarder.announcedIncoming) {
                    CallForwarder.startIncoming(context, CallForwarder.number)
                }
            }
            state == TelephonyManager.CALL_STATE_OFFHOOK &&
                lastState == TelephonyManager.CALL_STATE_RINGING -> {
                CallForwarder.send(context, "answered", CallForwarder.number,
                    CallForwarder.callId ?: UUID.randomUUID().toString())
            }
            state == TelephonyManager.CALL_STATE_IDLE &&
                lastState == TelephonyManager.CALL_STATE_RINGING -> {
                CallForwarder.send(context, "missed", CallForwarder.number,
                    CallForwarder.callId ?: UUID.randomUUID().toString())
                CallForwarder.reset()
            }
            state == TelephonyManager.CALL_STATE_IDLE &&
                lastState == TelephonyManager.CALL_STATE_OFFHOOK -> {
                CallForwarder.callId?.let {
                    CallForwarder.send(context, "ended", CallForwarder.number, it)
                }
                CallForwarder.reset()
            }
        }
        lastState = state
    }
}
