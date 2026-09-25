package com.hari.otpbridge

import android.content.Context
import kotlinx.serialization.json.Json

/** Persists the scanned pairing config in SharedPreferences. */
class PairingStore(context: Context) {
    private val prefs = context.getSharedPreferences("pairing", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    val isPaired: Boolean get() = prefs.contains("config")

    var config: PairingConfig?
        get() = prefs.getString("config", null)?.let {
            runCatching { json.decodeFromString<PairingConfig>(it) }.getOrNull()
        }
        set(value) {
            if (value == null) prefs.edit().remove("config").apply()
            else prefs.edit().putString("config", json.encodeToString(PairingConfig.serializer(), value)).apply()
        }

    /** Parse and store a scanned QR payload. Returns true if valid. */
    fun pairFrom(qr: String): Boolean {
        val cfg = runCatching { json.decodeFromString<PairingConfig>(qr) }.getOrNull() ?: return false
        if (cfg.key.isBlank() || cfg.room.isBlank()) return false
        config = cfg
        return true
    }
}
