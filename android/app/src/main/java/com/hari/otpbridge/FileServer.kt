package com.hari.otpbridge

import android.content.ContentValues
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import kotlinx.serialization.json.Json
import java.io.DataInputStream
import java.io.File
import java.net.ServerSocket
import kotlin.concurrent.thread

/**
 * Receives files from the Mac over LAN. Runs a TCP server, advertises it via
 * NSD as `_obfand._tcp`, and saves incoming files to the Downloads collection.
 * Frame format matches FileSender/FileReceiver:
 *   [4-byte BE length][1-byte type][nonce(12)||ct||tag]
 *   type 0 = header (FileMeta JSON), 1 = chunk, 2 = end.
 */
class FileServer(private val context: Context) {
    private var server: ServerSocket? = null
    private var nsd: NsdManager? = null
    private var regListener: NsdManager.RegistrationListener? = null
    @Volatile private var running = false

    fun start() {
        if (running) return
        running = true
        thread(name = "otpbridge-fileserver") {
            runCatching {
                val ss = ServerSocket(0)   // ephemeral port
                server = ss
                register(ss.localPort)
                while (running) {
                    val socket = ss.accept()
                    thread { handle(socket) }
                }
            }.onFailure { Log.d(TAG, "server error: ${it.message}") }
        }
    }

    private fun register(port: Int) {
        val info = NsdServiceInfo().apply {
            serviceName = "OTPBridgePhone"
            serviceType = "_obfand._tcp"
            setPort(port)
        }
        val mgr = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(s: NsdServiceInfo) { Log.d(TAG, "registered on $port") }
            override fun onRegistrationFailed(s: NsdServiceInfo, e: Int) { Log.d(TAG, "reg failed $e") }
            override fun onServiceUnregistered(s: NsdServiceInfo) {}
            override fun onUnregistrationFailed(s: NsdServiceInfo, e: Int) {}
        }
        mgr.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
        nsd = mgr
        regListener = listener
    }

    private fun handle(socket: java.net.Socket) {
        val cfg = PairingStore(context).config ?: return
        runCatching {
            socket.use {
                val input = DataInputStream(it.getInputStream())
                var name = "file"
                var mime = "application/octet-stream"
                var tmp: File? = null
                var out: java.io.OutputStream? = null

                while (true) {
                    val len = try { input.readInt() } catch (e: Exception) { break }
                    if (len <= 0 || len > 8 * 1024 * 1024) break
                    val frame = ByteArray(len)
                    input.readFully(frame)

                    val type = frame[0].toInt()
                    val nonce = frame.copyOfRange(1, 13)
                    val ctTag = frame.copyOfRange(13, frame.size)
                    val plain = Crypto.openRaw(cfg.key, cfg.room, nonce, ctTag)

                    when (type) {
                        0 -> {
                            val meta = Json { ignoreUnknownKeys = true }
                                .decodeFromString(FileMeta.serializer(), String(plain, Charsets.UTF_8))
                            name = meta.name.ifBlank { "file" }
                            mime = meta.mime
                            tmp = File.createTempFile("obf", null, context.cacheDir)
                            out = tmp!!.outputStream()
                        }
                        1 -> out?.write(plain)
                        2 -> {
                            out?.flush(); out?.close()
                            tmp?.let { f -> saveToDownloads(f, name, mime) }
                        }
                    }
                }
                out?.close()
            }
        }.onFailure { Log.d(TAG, "handle error: ${it.message}") }
    }

    private fun saveToDownloads(tmp: File, name: String, mime: String) {
        val resolver = context.contentResolver
        var viewUri: android.net.Uri? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri != null) {
                resolver.openOutputStream(uri)?.use { os -> tmp.inputStream().use { it.copyTo(os) } }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                viewUri = uri   // content://media/... — viewable by other apps
            }
        } else {
            @Suppress("DEPRECATION")
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val dest = File(dir, name)
            tmp.copyTo(dest, overwrite = true)
            viewUri = androidx.core.content.FileProvider.getUriForFile(
                context, "${context.packageName}.fileprovider", dest
            )
        }
        tmp.delete()
        FileNotify.show(context, name, viewUri, mime)
    }

    fun stop() {
        running = false
        runCatching { regListener?.let { nsd?.unregisterService(it) } }
        runCatching { server?.close() }
    }

    companion object {
        private const val TAG = "OtpBridgeFileSrv"
    }
}
