package com.hari.otpbridge

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.widget.Toast

/**
 * Invisible activity that copies text to the clipboard. Launched from the
 * "Text from Mac" notification — background services can't write the clipboard
 * on modern Android, but a foreground activity can.
 */
class CopyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent.getStringExtra(EXTRA_TEXT)?.let { text ->
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("OTP Bridge", text))
            Toast.makeText(this, "Copied", Toast.LENGTH_SHORT).show()
        }
        finish()
    }

    companion object {
        const val EXTRA_TEXT = "text"
    }
}
