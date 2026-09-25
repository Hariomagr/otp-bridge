package com.hari.otpbridge

import android.telecom.Call
import android.telecom.CallScreeningService

/**
 * Holds the call-screening role so we get the caller's number at ring time
 * (PHONE_STATE alone doesn't provide it on many devices). We don't block any
 * call — we just read the number, announce the incoming call to the Mac, and
 * always allow it through.
 */
class CallScreener : CallScreeningService() {
    override fun onScreenCall(details: Call.Details) {
        if (details.callDirection == Call.Details.DIRECTION_INCOMING &&
            PairingStore(this).isPaired
        ) {
            val number = details.handle?.schemeSpecificPart
            CallForwarder.startIncoming(this, number)
        }
        // Always allow the call; we only wanted the caller info.
        respondToCall(details, CallResponse.Builder().build())
    }
}
