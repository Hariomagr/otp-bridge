package com.hari.otpbridge

import android.util.Base64
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM matching PROTOCOL.md (verified byte-compatible with the Node
 * relay and the Swift Mac app). `ct` = ciphertext||tag; AAD = utf8(room).
 */
object Crypto {
    private val rng = SecureRandom()

    fun seal(keyB64: String, room: String, plaintext: String): Envelope {
        val key = SecretKeySpec(Base64.decode(keyB64, Base64.NO_WRAP), "AES")
        val nonce = ByteArray(12).also { rng.nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, nonce))
        cipher.updateAAD(room.toByteArray(Charsets.UTF_8))
        val ctFull = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return Envelope(
            room = room,
            nonce = Base64.encodeToString(nonce, Base64.NO_WRAP),
            ct = Base64.encodeToString(ctFull, Base64.NO_WRAP),
        )
    }

    /** Raw binary seal for file frames: returns nonce(12) || ciphertext || tag. */
    fun sealRaw(keyB64: String, room: String, plaintext: ByteArray): ByteArray {
        val key = SecretKeySpec(Base64.decode(keyB64, Base64.NO_WRAP), "AES")
        val nonce = ByteArray(12).also { rng.nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, nonce))
        cipher.updateAAD(room.toByteArray(Charsets.UTF_8))
        return nonce + cipher.doFinal(plaintext)   // nonce || ct || tag
    }

    /** Raw binary open for file frames. nonce = 12 bytes, ctTag = ciphertext||tag. */
    fun openRaw(keyB64: String, room: String, nonce: ByteArray, ctTag: ByteArray): ByteArray {
        val key = SecretKeySpec(Base64.decode(keyB64, Base64.NO_WRAP), "AES")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
        cipher.updateAAD(room.toByteArray(Charsets.UTF_8))
        return cipher.doFinal(ctTag)
    }

    /** Kept for future Mac->phone messages. */
    fun open(keyB64: String, room: String, nonceB64: String, ctB64: String): String {
        val key = SecretKeySpec(Base64.decode(keyB64, Base64.NO_WRAP), "AES")
        val nonce = Base64.decode(nonceB64, Base64.NO_WRAP)
        val ctFull = Base64.decode(ctB64, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
        cipher.updateAAD(room.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(ctFull), Charsets.UTF_8)
    }
}
