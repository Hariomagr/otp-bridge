package com.hari.otpbridge

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import java.util.UUID

/**
 * Receives text shared from any app (Android share sheet) and forwards it to
 * the Mac through the encrypted pipeline.
 */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!text.isNullOrEmpty() && PairingStore(this).isPaired) {
                ForwardService.forward(
                    this,
                    OtpMessage(
                        id = UUID.randomUUID().toString(),
                        ts = System.currentTimeMillis(),
                        source = "TEXT",
                        title = "Shared text",
                        text = text,
                        kind = "text",
                    )
                )
                Toast.makeText(this, "Sent to Mac", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "Pair with the Mac first", Toast.LENGTH_SHORT).show()
            }
        }
        finish()
    }
}
