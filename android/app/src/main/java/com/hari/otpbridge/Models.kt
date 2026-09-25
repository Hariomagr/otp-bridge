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
