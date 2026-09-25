package com.hari.otpbridge

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.UUID

class MainActivity : ComponentActivity() {

    // Bumped on resume so the UI re-checks permission / battery state after the
    // user returns from a system dialog or the settings screen.
    private val refresh = mutableIntStateOf(0)

    override fun onResume() {
        super.onResume()
        refresh.intValue++
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val store = PairingStore(this)

        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val tick = refresh.intValue
                    var status by remember { mutableStateOf(pairStatus(store)) }
                    val permsGranted = remember(tick) { hasAllPermissions() }
                    val batteryOk = remember(tick) { isIgnoringBatteryOptimizations() }

                    // Is the Mac reachable? On LAN (service discoverable) or on
                    // the relay (peer present). Re-probed on resume and after pairing.
                    var reachable by remember { mutableStateOf(false) }
                    var checking by remember { mutableStateOf(false) }
                    LaunchedEffect(tick, status) {
                        if (!store.isPaired) { reachable = false; return@LaunchedEffect }
                        checking = true
                        reachable = withContext(Dispatchers.IO) {
                            val cfg = store.config ?: return@withContext false
                            LanSender.isMacOnLan(applicationContext) ||
                                RelayClient.checkPresence(cfg.relay, cfg.room)
                        }
                        checking = false
                    }

                    val permLauncher = rememberLauncherForActivityResult(
                        ActivityResultContracts.RequestMultiplePermissions()
                    ) { refresh.intValue++ }

                    Column(
                        modifier = Modifier.fillMaxSize().padding(24.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text("OTP Bridge", style = MaterialTheme.typography.headlineSmall)
                        Text(status)

                        if (!permsGranted) {
                            Button(onClick = { permLauncher.launch(requiredPermissions()) }) {
                                Text("Grant SMS & notification permissions")
                            }
                        }

                        Button(onClick = {
                            val options = GmsBarcodeScannerOptions.Builder()
                                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                                .build()
                            GmsBarcodeScanning.getClient(this@MainActivity, options)
                                .startScan()
                                .addOnSuccessListener { barcode ->
                                    val raw = barcode.rawValue
                                    status = if (raw != null && store.pairFrom(raw)) {
                                        "Paired with ${store.config?.name ?: "Mac"}"
                                    } else {
                                        "Pairing failed — scan the QR shown in the Mac app"
                                    }
                                    refresh.intValue++
                                }
                                .addOnCanceledListener { }
                                .addOnFailureListener {
                                    status = "Scanner error: ${it.message}"
                                }
                        }) { Text("Pair with Mac (scan QR)") }

                        if (!batteryOk) {
                            Button(onClick = { requestIgnoreBatteryOptimizations() }) {
                                Text("Disable battery optimization")
                            }
                        }

                        if (store.isPaired) {
                            Text(
                                when {
                                    checking -> "Checking if Mac is reachable…"
                                    reachable -> "Mac connected"
                                    else -> "Mac not connected (open the Mac app / same Wi-Fi)"
                                }
                            )
                        }

                        // Only offer the test send when the Mac can actually receive it.
                        if (reachable) {
                            Button(onClick = { sendTestMessage() }) {
                                Text("Send a test OTP to the Mac")
                            }
                        }
                    }
                }
            }
        }
    }

    private fun pairStatus(store: PairingStore): String =
        if (store.isPaired) "Paired with ${store.config?.name ?: "Mac"}"
        else "Not paired — scan the QR from the Mac app"

    private fun requiredPermissions(): Array<String> = buildList {
        add(Manifest.permission.RECEIVE_SMS)
        // Camera not needed: the ML Kit code scanner runs in Google Play Services.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }.toTypedArray()

    private fun hasAllPermissions(): Boolean = requiredPermissions().all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    @SuppressLint("BatteryLife")
    private fun requestIgnoreBatteryOptimizations() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:$packageName"))
        runCatching { startActivity(intent) }
    }

    private fun sendTestMessage() {
        val store = PairingStore(this)
        if (!store.isPaired) return
        ForwardService.forward(
            this,
            OtpMessage(
                id = UUID.randomUUID().toString(),
                ts = System.currentTimeMillis(),
                source = "SMS",
                sender = "TEST",
                title = "Test",
                text = "Your OTP is 483920. Valid 10 min.",
                code = "483920",
            )
        )
    }
}
