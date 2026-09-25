package com.hari.otpbridge

import android.content.Context
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.provider.OpenableColumns
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Sends a file to the Mac over LAN. Discovers the Mac's `_obfmac._tcp` service
 * via NSD, then streams length-prefixed encrypted frames:
 *   [4-byte BE length][ frame ]  where frame = [1-byte type][nonce(12)||ct||tag]
 *   type 0 = header (FileMeta JSON), 1 = chunk, 2 = end.
 *
 * Returns true on success. (Relay fallback for files is a later step; files are
 * large and best sent over LAN.)
 */
object FileSender {
    private const val SERVICE_TYPE = "_obfmac._tcp."
    private const val DISCOVERY_TIMEOUT_MS = 3000L
    private const val CONNECT_TIMEOUT_MS = 2000
    private const val CHUNK = 64 * 1024

    /** Progress update for the UI. */
    data class Progress(
        val index: Int,        // 1-based current file
        val total: Int,        // total files
        val name: String,      // current file name
        val sent: Long,        // bytes sent for current file
        val size: Long,        // current file size (0 if unknown)
        val done: Boolean = false,
        val ok: Int = 0,       // files fully sent so far
        val found: Boolean = true,
    )

    /** Send one file. */
    suspend fun send(context: Context, uri: Uri): Boolean =
        sendAll(context, listOf(uri)).first

    /**
     * Send multiple files. Discovers the Mac once, then sends each file on its
     * own connection. Reports progress via [onProgress] on a background thread.
     * Returns (allSucceeded, sentCount).
     */
    suspend fun sendAll(
        context: Context,
        uris: List<Uri>,
        onProgress: (Progress) -> Unit = {},
    ): Pair<Boolean, Int> {
        val cfg = PairingStore(context).config ?: return false to 0
        if (uris.isEmpty()) return false to 0
        val info = discover(context)
        val host = info?.host
        if (host == null) {
            onProgress(Progress(0, uris.size, "", 0, 0, done = true, ok = 0, found = false))
            return false to 0
        }

        var sent = 0
        uris.forEachIndexed { i, uri ->
            if (sendOne(context, cfg, host, info.port, uri, i + 1, uris.size, onProgress)) sent++
        }
        onProgress(Progress(uris.size, uris.size, "", 0, 0, done = true, ok = sent, found = true))
        return (sent == uris.size) to sent
    }

    private fun sendOne(
        context: Context, cfg: PairingConfig, host: java.net.InetAddress, port: Int,
        uri: Uri, index: Int, total: Int, onProgress: (Progress) -> Unit,
    ): Boolean {
        val (name, size) = queryMeta(context, uri)
        val mime = context.contentResolver.getType(uri) ?: "application/octet-stream"
        return runCatching {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
                val out = DataOutputStream(socket.getOutputStream())

                val header = Json.encodeToString(
                    FileMeta.serializer(),
                    FileMeta(id = java.util.UUID.randomUUID().toString(), name = name, mime = mime, size = size)
                ).toByteArray(Charsets.UTF_8)
                writeFrame(out, cfg, 0, header)

                var acc = 0L
                onProgress(Progress(index, total, name, 0, size.toLong()))
                context.contentResolver.openInputStream(uri)!!.use { input ->
                    val buf = ByteArray(CHUNK)
                    while (true) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        writeFrame(out, cfg, 1, buf.copyOf(n))
                        acc += n
                        onProgress(Progress(index, total, name, acc, size.toLong()))
                    }
                }

                writeFrame(out, cfg, 2, ByteArray(0))
                out.flush()
            }
            true
        }.getOrDefault(false)
    }

    private fun writeFrame(out: DataOutputStream, cfg: PairingConfig, type: Int, payload: ByteArray) {
        val sealed = Crypto.sealRaw(cfg.key, cfg.room, payload)   // nonce||ct||tag
        val frame = ByteArray(1 + sealed.size)
        frame[0] = type.toByte()
        System.arraycopy(sealed, 0, frame, 1, sealed.size)
        out.writeInt(frame.size)   // 4-byte big-endian length
        out.write(frame)
    }

    private fun queryMeta(context: Context, uri: Uri): Pair<String, Int> {
        var name = "file"
        var size = 0
        runCatching {
            context.contentResolver.query(uri, null, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val si = c.getColumnIndex(OpenableColumns.SIZE)
                    if (ni >= 0) name = c.getString(ni) ?: name
                    if (si >= 0) size = c.getInt(si)
                }
            }
        }
        return name to size
    }

    private suspend fun discover(context: Context): NsdServiceInfo? {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val resolved = CompletableDeferred<NsdServiceInfo?>()

        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(s: NsdServiceInfo?, e: Int) { resolved.complete(null) }
            override fun onServiceResolved(s: NsdServiceInfo) { resolved.complete(s) }
        }
        val discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(t: String?, e: Int) { resolved.complete(null) }
            override fun onStopDiscoveryFailed(t: String?, e: Int) {}
            override fun onDiscoveryStarted(t: String?) {}
            override fun onDiscoveryStopped(t: String?) {}
            override fun onServiceLost(s: NsdServiceInfo?) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.contains("_obfmac._tcp")) {
                    @Suppress("DEPRECATION")
                    nsd.resolveService(service, resolveListener)
                }
            }
        }

        val info = withTimeoutOrNull(DISCOVERY_TIMEOUT_MS) {
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
            resolved.await()
        }
        runCatching { nsd.stopServiceDiscovery(discoveryListener) }
        return info
    }
}
