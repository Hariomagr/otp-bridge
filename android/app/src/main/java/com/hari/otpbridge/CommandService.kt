package com.hari.otpbridge

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

/**
 * Long-lived foreground service that keeps a WebSocket to the relay open so the
 * Mac can send commands back to the phone (currently: reject a ringing call).
 * Uses the relay because it works whether or not the phone is on the Mac's LAN.
 */
class CommandService : Service() {

    private val client = OkHttpClient.Builder()
        .pingInterval(30, TimeUnit.SECONDS)
        .build()
    private val json = Json { ignoreUnknownKeys = true }
    private var ws: WebSocket? = null
    private var stopped = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIF_ID, buildNotification())
        connect()
        return START_STICKY
    }

    private fun connect() {
        val cfg = PairingStore(this).config
        if (cfg == null || cfg.relay.isBlank()) {
            // No reverse channel possible without a relay; idle in foreground.
            return
        }
        ws?.cancel()
        Log.d(TAG, "connecting to relay ${cfg.relay}")
        ws = client.newWebSocket(
            Request.Builder().url(cfg.relay).build(),
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    Log.d(TAG, "relay open; joining room ${cfg.room.take(8)}…")
                    webSocket.send("""{"type":"join","room":"${cfg.room}"}""")
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    Log.d(TAG, "frame: ${text.take(60)}")
                    handleFrame(cfg, text)
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    Log.d(TAG, "relay failure: ${t.message}")
                    if (!stopped) reconnectSoon()
                }
            }
        )
    }

    private fun handleFrame(cfg: PairingConfig, text: String) {
        val obj = runCatching { json.parseToJsonElement(text).jsonObject }.getOrNull() ?: return
        if (obj["type"]?.jsonPrimitive?.content != "msg") return
        val nonce = obj["nonce"]?.jsonPrimitive?.content ?: return
        val ct = obj["ct"]?.jsonPrimitive?.content ?: return

        val plaintext = runCatching { Crypto.open(cfg.key, cfg.room, nonce, ct) }.getOrNull()
        if (plaintext == null) { Log.d(TAG, "decrypt failed"); return }
        val payload = runCatching { json.parseToJsonElement(plaintext).jsonObject }.getOrNull() ?: return
        if (payload["kind"]?.jsonPrimitive?.content != "cmd") return

        val cmd = payload["cmd"]?.jsonPrimitive?.content
        Log.d(TAG, "command received: $cmd")
        when (cmd) {
            "reject_call" -> endCall()
            "accept_call" -> acceptCall()
        }
    }

    private fun endCall() {
        if (!hasAnswerPermission()) { Log.d(TAG, "endCall: no ANSWER_PHONE_CALLS"); return }
        val tm = getSystemService(TelecomManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val ok = runCatching { tm.endCall() }.getOrElse { Log.d(TAG, "endCall err: ${it.message}"); false }
            Log.d(TAG, "endCall -> $ok")
        }
    }

    @Suppress("DEPRECATION")
    private fun acceptCall() {
        if (!hasAnswerPermission()) { Log.d(TAG, "acceptCall: no ANSWER_PHONE_CALLS"); return }
        val tm = getSystemService(TelecomManager::class.java) ?: return
        runCatching { tm.acceptRingingCall() }.onFailure { Log.d(TAG, "acceptCall err: ${it.message}") }
        Log.d(TAG, "acceptCall invoked")
    }

    private fun hasAnswerPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ANSWER_PHONE_CALLS) ==
            PackageManager.PERMISSION_GRANTED

    private fun reconnectSoon() {
        ws = null
        Thread {
            Thread.sleep(3000)
            if (!stopped) connect()
        }.start()
    }

    override fun onDestroy() {
        stopped = true
        ws?.cancel()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            mgr.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "OTP Bridge link", NotificationManager.IMPORTANCE_MIN)
            )
        }
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("OTP Bridge")
            .setContentText("Connected — forwarding messages & calls")
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .build()
    }

    companion object {
        private const val TAG = "OtpBridgeCmd"
        private const val CHANNEL_ID = "otp_link"
        private const val NOTIF_ID = 43

        fun start(context: Context) {
            context.startForegroundService(Intent(context, CommandService::class.java))
        }
    }
}
