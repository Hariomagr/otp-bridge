package com.hari.otpbridge

import kotlinx.serialization.Serializable

@Serializable
data class OtpMessage(
    val id: String,
    val ts: Long,
    val source: String,
    val sender: String? = null,
    val title: String? = null,
    val text: String,
    val code: String? = null,
    val kind: String = "sms",       // "sms" | "call" | "text" | "file"
    val number: String? = null,     // call: raw number
    val name: String? = null,       // call: resolved contact name
    val callState: String? = null,  // call: "incoming" | "missed"
)

/** File-transfer header, sent as the first frame of a LAN transfer. */
@Serializable
data class FileMeta(
    val id: String,
    val name: String,
    val mime: String,
    val size: Int,
)

/** Mac -> phone command (e.g. reject a ringing call). */
@Serializable
data class Command(
    val kind: String = "cmd",
    val cmd: String,        // "reject_call"
    val callId: String,
)

@Serializable
data class Envelope(
    val room: String,
    val nonce: String,
    val ct: String,
)

/** Decoded from the QR the Mac shows. */
@Serializable
data class PairingConfig(
    val v: Int,
    val key: String,
    val room: String,
    val relay: String,
    val name: String,
)
