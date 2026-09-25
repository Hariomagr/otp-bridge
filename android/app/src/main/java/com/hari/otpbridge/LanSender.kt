package com.hari.otpbridge

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import java.net.InetSocketAddress
import java.net.Socket

/**
 * LAN delivery: discover the Mac's `_otpbridge._tcp` service via NSD, then push
 * the newline-terminated envelope over a plain TCP socket. Returns true on a
 * successful write. All best-effort with a tight timeout so the relay fallback
 * kicks in quickly when the Mac isn't reachable.
 */
object LanSender {
    private const val SERVICE_TYPE = "_otpbridge._tcp."
    private const val DISCOVERY_TIMEOUT_MS = 2500L
    private const val CONNECT_TIMEOUT_MS = 1500

    suspend fun send(context: Context, envelopeJson: String): Boolean {
        val info = discover(context) ?: return false
        val host = info.host ?: return false
        return runCatching {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, info.port), CONNECT_TIMEOUT_MS)
                socket.getOutputStream().apply {
                    write((envelopeJson + "\n").toByteArray(Charsets.UTF_8))
                    flush()
                }
            }
            true
        }.getOrDefault(false)
    }

    /** True if the Mac's service is discoverable and a TCP connection succeeds. */
    suspend fun isMacOnLan(context: Context): Boolean {
        val info = discover(context) ?: return false
        val host = info.host ?: return false
        return runCatching {
            Socket().use { it.connect(InetSocketAddress(host, info.port), CONNECT_TIMEOUT_MS) }
            true
        }.getOrDefault(false)
    }

    /** Discover and resolve the Mac's service, or null within the timeout. */
    private suspend fun discover(context: Context): NsdServiceInfo? {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val resolved = CompletableDeferred<NsdServiceInfo?>()

        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) {
                resolved.complete(null)
            }
            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                resolved.complete(serviceInfo)
            }
        }

        val discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(t: String?, e: Int) { resolved.complete(null) }
            override fun onStopDiscoveryFailed(t: String?, e: Int) {}
            override fun onDiscoveryStarted(t: String?) {}
            override fun onDiscoveryStopped(t: String?) {}
            override fun onServiceLost(s: NsdServiceInfo?) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.contains("_otpbridge._tcp")) {
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
