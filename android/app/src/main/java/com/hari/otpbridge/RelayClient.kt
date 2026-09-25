package com.hari.otpbridge

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

/**
 * Relay fallback: open a WebSocket, join the room, send the envelope as a
 * `msg` frame, then close. One-shot per message keeps the service simple; the
 * connection cost is a few hundred ms which is fine for OTP latency.
 */
object RelayClient {
    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .build()

    suspend fun send(relayUrl: String, env: Envelope): Boolean {
        if (relayUrl.isBlank()) return false
        val done = CompletableDeferred<Boolean>()

        val listener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"join","room":"${env.room}"}""")
                val msg = buildJsonMsg(env)
                webSocket.send(msg)
                // Give the frame a moment to flush before closing.
                webSocket.close(1000, null)
                done.complete(true)
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                done.complete(false)
            }
        }

        val request = Request.Builder().url(relayUrl).build()
        val ws = client.newWebSocket(request, listener)
        val ok = withTimeoutOrNull(6000) { done.await() } ?: false
        if (!ok) ws.cancel()
        return ok
    }

    /**
     * Presence probe: connect, join the room, and read the peer count the relay
     * reports. peers > 0 means the Mac is currently connected to the relay.
     */
    suspend fun checkPresence(relayUrl: String, room: String): Boolean {
        if (relayUrl.isBlank()) return false
        val done = CompletableDeferred<Boolean>()

        val listener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"join","room":"$room"}""")
            }
            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = runCatching { Json.parseToJsonElement(text).jsonObject }.getOrNull()
                if (obj?.get("type")?.jsonPrimitive?.content == "joined") {
                    val peers = obj["peers"]?.jsonPrimitive?.intOrNull ?: 0
                    done.complete(peers > 0)
                    webSocket.close(1000, null)
                }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                done.complete(false)
            }
        }

        val ws = client.newWebSocket(Request.Builder().url(relayUrl).build(), listener)
        val ok = withTimeoutOrNull(5000) { done.await() } ?: false
        if (!ok) ws.cancel()
        return ok
    }

    private fun buildJsonMsg(env: Envelope): String {
        val obj = JsonObject(
            mapOf(
                "type" to JsonPrimitive("msg"),
                "room" to JsonPrimitive(env.room),
                "nonce" to JsonPrimitive(env.nonce),
                "ct" to JsonPrimitive(env.ct),
            )
        )
        return Json.encodeToString(JsonObject.serializer(), obj)
    }
}
