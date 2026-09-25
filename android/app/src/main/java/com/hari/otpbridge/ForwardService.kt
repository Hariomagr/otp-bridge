package com.hari.otpbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json

/**
 * Foreground service that encrypts a message and pushes it to the Mac over LAN
 * and relay concurrently. The Mac dedupes on `id`, so double delivery is fine.
 */
class ForwardService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIF_ID, buildNotification())

        val payload = intent?.getStringExtra(EXTRA_MESSAGE)
        val message = payload?.let { runCatching { json.decodeFromString<OtpMessage>(it) }.getOrNull() }
        val config = PairingStore(this).config

        if (message == null || config == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        scope.launch {
            val env = Crypto.seal(config.key, config.room,
                json.encodeToString(OtpMessage.serializer(), message))

            // Fire both paths; either reaching the Mac is enough.
            val results = listOf(
                async { LanSender.send(applicationContext, json.encodeToString(Envelope.serializer(), env)) },
                async { RelayClient.send(config.relay, env) },
            ).awaitAll()

            // (results could feed a retry queue; out of scope for the skeleton.)
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "OTP forwarding", NotificationManager.IMPORTANCE_LOW
            )
            mgr.createNotificationChannel(channel)
        }
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("OTP Bridge")
            .setContentText("Forwarding a code to your Mac…")
            .setSmallIcon(NotifIcons.small)
            .setLargeIcon(NotifIcons.large(this))
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "otp_forward"
        private const val NOTIF_ID = 42
        const val EXTRA_MESSAGE = "message_json"

        fun forward(context: Context, message: OtpMessage) {
            val json = Json { ignoreUnknownKeys = true }
            val intent = Intent(context, ForwardService::class.java)
                .putExtra(EXTRA_MESSAGE, json.encodeToString(OtpMessage.serializer(), message))
            context.startForegroundService(intent)
        }
    }
}
