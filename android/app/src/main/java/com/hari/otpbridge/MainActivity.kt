package com.hari.otpbridge

import android.Manifest
import android.annotation.SuppressLint
import android.app.role.RoleManager
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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

class MainActivity : ComponentActivity() {

    // Bumped on resume so the UI re-checks permission / battery state after the
    // user returns from a system dialog or the settings screen.
    private val refresh = mutableIntStateOf(0)

    override fun onResume() {
        super.onResume()
        refresh.intValue++
        // Keep the reverse-command link alive whenever the app is opened.
        if (PairingStore(this).isPaired) runCatching { CommandService.start(this) }
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
                    val screeningHeld = remember(tick) { isScreeningRoleHeld() }

                    val roleLauncher = rememberLauncherForActivityResult(
                        ActivityResultContracts.StartActivityForResult()
                    ) { refresh.intValue++ }

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

                    var transfer by remember { mutableStateOf<FileSender.Progress?>(null) }
                    var transferResult by remember { mutableStateOf<String?>(null) }

                    val fileLauncher = rememberLauncherForActivityResult(
                        ActivityResultContracts.GetMultipleContents()
                    ) { uris ->
                        if (!uris.isNullOrEmpty()) {
                            transferResult = null
                            transfer = FileSender.Progress(0, uris.size, "", 0, 0)
                            kotlinx.coroutines.MainScope().launch {
                                val (allOk, sent) = withContext(Dispatchers.IO) {
                                    FileSender.sendAll(applicationContext, uris) { p ->
                                        MainScope().launch { transfer = p }
                                    }
                                }
                                transfer = null
                                transferResult = when {
                                    sent == 0 -> "Send failed — is the Mac open on the same Wi-Fi?"
                                    allOk -> "Sent $sent file(s) to Mac ✓"
                                    else -> "Sent $sent of ${uris.size} (some failed)"
                                }
                            }
                        }
                    }

                    // Xender-style transfer overlay.
                    transfer?.let { p ->
                        TransferDialog(p)
                    }
                    transferResult?.let { msg ->
                        androidx.compose.material3.AlertDialog(
                            onDismissRequest = { transferResult = null },
                            confirmButton = {
                                androidx.compose.material3.TextButton(onClick = { transferResult = null }) {
                                    Text("OK")
                                }
                            },
                            title = { Text("Transfer") },
                            text = { Text(msg) },
                        )
                    }

                    val allSetupDone = permsGranted && batteryOk &&
                        (screeningHeld || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)

                    Column(
                        modifier = Modifier.fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(24.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text("OTP Bridge", style = MaterialTheme.typography.headlineSmall)
                        Text(status)

                        // --- Setup (buttons vanish as each step is satisfied) ---
                        if (!allSetupDone || !store.isPaired) {
                            Text("Setup", style = MaterialTheme.typography.titleMedium)
                        }

                        if (!permsGranted) {
                            Button(
                                onClick = { permLauncher.launch(requiredPermissions()) },
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("Grant SMS & notification permissions") }
                        }

                        Button(modifier = Modifier.fillMaxWidth(), onClick = {
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
                        }) { Text(if (store.isPaired) "Re-pair with Mac (scan QR)" else "Pair with Mac (scan QR)") }

                        if (!batteryOk) {
                            Button(
                                onClick = { requestIgnoreBatteryOptimizations() },
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("Disable battery optimization") }
                        }

                        // Call-screening role: lets us show the caller's number/name
                        // at ring time (Recommended for reliable caller ID).
                        if (!screeningHeld && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            Button(
                                onClick = {
                                    val rm = getSystemService(RoleManager::class.java)
                                    if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING)) {
                                        roleLauncher.launch(rm.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING))
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("Enable caller ID (call screening)") }
                        }

                        // --- Share section (only when paired) ---
                        if (store.isPaired) {
                            HorizontalDivider()
                            Text("Share with Mac", style = MaterialTheme.typography.titleMedium)
                            Text(
                                when {
                                    checking -> "Checking if Mac is reachable…"
                                    reachable -> "● Mac connected"
                                    else -> "○ Mac not connected (open the Mac app / same Wi-Fi)"
                                },
                                style = MaterialTheme.typography.bodySmall,
                            )

                            var draft by remember { mutableStateOf("") }
                            OutlinedTextField(
                                value = draft,
                                onValueChange = { draft = it },
                                label = { Text("Text to send") },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Button(
                                onClick = {
                                    if (draft.isNotBlank()) {
                                        ForwardService.forward(
                                            this@MainActivity,
                                            OtpMessage(
                                                id = java.util.UUID.randomUUID().toString(),
                                                ts = System.currentTimeMillis(),
                                                source = "TEXT",
                                                title = "Shared text",
                                                text = draft,
                                                kind = "text",
                                            )
                                        )
                                        draft = ""
                                    }
                                },
                                enabled = draft.isNotBlank(),
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("Send text") }

                            Button(
                                onClick = { fileLauncher.launch("*/*") },
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("Send files / images to Mac") }

                            // Test OTP only when reachable.
                            if (reachable) {
                                OutlinedButton(
                                    onClick = { sendTestMessage() },
                                    modifier = Modifier.fillMaxWidth(),
                                ) { Text("Send a test OTP") }
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
        add(Manifest.permission.READ_PHONE_STATE)
        add(Manifest.permission.READ_CALL_LOG)
        add(Manifest.permission.READ_CONTACTS)
        add(Manifest.permission.ANSWER_PHONE_CALLS)
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

    private fun isScreeningRoleHeld(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val rm = getSystemService(RoleManager::class.java) ?: return false
        return rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
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

/** Xender-style transfer progress overlay (non-dismissable while sending). */
@Composable
private fun TransferDialog(p: FileSender.Progress) {
    AlertDialog(
        onDismissRequest = { },   // block dismiss during transfer
        confirmButton = {},
        title = { Text("Sending to Mac") },
        text = {
            Column {
                val label = if (p.index > 0) "File ${p.index} of ${p.total}" else "Connecting…"
                Text(label, style = MaterialTheme.typography.titleSmall)
                Spacer(Modifier.height(6.dp))
                if (p.name.isNotEmpty()) {
                    Text(p.name, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.bodyMedium)
                    Spacer(Modifier.height(8.dp))
                }
                if (p.size > 0) {
                    val frac = (p.sent.toFloat() / p.size).coerceIn(0f, 1f)
                    LinearProgressIndicator(progress = { frac }, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(4.dp))
                    Text("${p.sent / 1024} / ${p.size / 1024} KB",
                        style = MaterialTheme.typography.bodySmall)
                } else {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
                Spacer(Modifier.height(10.dp))
                Text("Keep this app open until the transfer finishes.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
        },
    )
}
