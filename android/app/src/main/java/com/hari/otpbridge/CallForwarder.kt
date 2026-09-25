package com.hari.otpbridge

import android.content.Context
import android.net.Uri
import android.provider.ContactsContract
import java.util.UUID

/**
 * Shared call-event state and sender, used by both CallScreener (which gets the
 * caller number at ring time via the call-screening role) and CallReceiver
 * (which tracks answered/missed/ended via PHONE_STATE).
 */
object CallForwarder {
    @Volatile var callId: String? = null
    @Volatile var number: String? = null
    @Volatile var announcedIncoming = false

    /** Announce a ringing call (called by the screener, or by the receiver as a fallback). */
    @Synchronized
    fun startIncoming(context: Context, number: String?): String {
        val id = UUID.randomUUID().toString()
        callId = id
        if (!number.isNullOrBlank()) this.number = number
        announcedIncoming = true
        send(context, "incoming", this.number, id)
        return id
    }

    fun updateNumber(n: String?) {
        if (!n.isNullOrBlank()) number = n
    }

    @Synchronized
    fun reset() {
        callId = null
        number = null
        announcedIncoming = false
    }

    fun send(context: Context, callState: String, number: String?, id: String) {
        val name = lookupContactName(context, number)
        val display = name ?: number ?: "Unknown"
        val text = when (callState) {
            "incoming" -> "Incoming call from $display"
            "missed" -> "Missed call from $display"
            else -> "Call from $display"          // answered / ended
        }
        ForwardService.forward(
            context,
            OtpMessage(
                id = id,
                ts = System.currentTimeMillis(),
                source = "CALL",
                sender = number,
                title = name ?: number ?: "Unknown",
                text = text,
                code = null,
                kind = "call",
                number = number,
                name = name,
                callState = callState,
            )
        )
    }

    private fun lookupContactName(context: Context, number: String?): String? {
        if (number.isNullOrBlank()) return null
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number)
        )
        return runCatching {
            context.contentResolver.query(
                uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null
            )?.use { if (it.moveToFirst()) it.getString(0) else null }
        }.getOrNull()
    }
}
