package com.hari.otpbridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import java.util.UUID

/**
 * Fires on every incoming SMS. Reassembles multipart bodies, extracts the OTP,
 * and hands the message to the foreground service for delivery.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!PairingStore(context).isPaired) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return

        val sender = messages.first().originatingAddress
        val body = messages.joinToString("") { it.messageBody ?: "" }
        if (body.isBlank()) return

        val message = OtpMessage(
            id = UUID.randomUUID().toString(),
            ts = System.currentTimeMillis(),
            source = "SMS",
            sender = sender,
            title = sender,
            text = body,
            code = OtpExtractor.extract(body),
        )
        ForwardService.forward(context, message)
    }
}
