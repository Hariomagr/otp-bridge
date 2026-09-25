import SwiftUI
import AppKit
import UserNotifications

// MARK: - App model (router + state)

@MainActor
final class AppModel: ObservableObject {
    let pairing = PairingStore()

    @Published var lanReady = false
    @Published var relayConnected = false
    @Published var lastMessage: OTPMessage?
    @Published var relayField = ""
    @Published var relayLocked = false          // field read-only until "Change"
    @Published var relayEnabled = true          // relay delivery on/off (URL kept)
    @Published var messages: [OTPMessage] = []  // full history, newest first
    @Published var activeCall: OTPMessage?      // currently ringing incoming call

    private var lan: LANListener?
    private var relay: RelayClient?
    private var fileReceiver: FileReceiver?
    private lazy var fileSender = FileSender(cryptoProvider: { [weak self] in self?.pairing.crypto })
    private let clipboardClearAfter: TimeInterval = 60
    private let messageStore = MessageStore()
    private var rejectedCallIds = Set<String>()   // ignore late churn after reject

    func start() {
        relayField = pairing.config.relay
        relayLocked = !pairing.config.relay.isEmpty
        relayEnabled = UserDefaults.standard.object(forKey: "relayEnabled") as? Bool ?? true
        messages = messageStore.load()

        lan = LANListener(
            onEnvelope: { [weak self] env in Task { @MainActor in self?.handle(env) } },
            onState:    { [weak self] up  in Task { @MainActor in self?.lanReady = up } }
        )
        lan?.start()

        relay = RelayClient(
            room: pairing.config.room,
            onEnvelope: { [weak self] env in Task { @MainActor in self?.handle(env) } },
            onState:    { [weak self] up  in Task { @MainActor in self?.relayConnected = up } }
        )
        if relayEnabled && !pairing.config.relay.isEmpty {
            relay?.connect(to: pairing.config.relay)
        }

        fileReceiver = FileReceiver(
            cryptoProvider: { [weak self] in self?.pairing.crypto },
            onFile: { [weak self] name, url in Task { @MainActor in self?.onFileReceived(name, url) } }
        )
        fileReceiver?.start()
    }

    private func onFileReceived(_ name: String, _ url: URL) {
        let msg = OTPMessage(
            id: UUID().uuidString, ts: Date().timeIntervalSince1970 * 1000,
            source: "FILE", sender: nil, title: "Received file", text: "Received \(name)",
            code: nil, kind: "file", number: nil, name: nil, callState: nil,
            fileName: name, localPath: url.path
        )
        messages.insert(msg, at: 0)
        messageStore.save(messages)
        lastMessage = msg
        Notifications.presentFile(name)
    }

    func revealFile(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @Published var fileSendStatus: String?

    /// Send files from the Mac to the phone over LAN.
    func sendFilesToPhone(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        fileSendStatus = "Sending \(urls.count) file(s)…"
        fileSender.send(urls) { [weak self] sent, found in
            guard let self else { return }
            if !found {
                self.fileSendStatus = "Phone not found on Wi-Fi"
            } else {
                self.fileSendStatus = sent == urls.count
                    ? "Sent \(sent) file(s) to phone"
                    : "Sent \(sent)/\(urls.count) (some failed)"
                for url in urls {
                    let m = OTPMessage(id: UUID().uuidString, ts: Date().timeIntervalSince1970 * 1000,
                                       source: "You → Phone", sender: nil, title: "Sent file",
                                       text: "Sent \(url.lastPathComponent)", code: nil, kind: "file",
                                       number: nil, name: nil, callState: nil,
                                       fileName: url.lastPathComponent, localPath: url.path)
                    self.messages.insert(m, at: 0)
                }
                self.messageStore.save(self.messages)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.fileSendStatus = nil }
        }
    }

    func applyRelay() {
        pairing.setRelay(relayField)
        relayField = pairing.config.relay   // reflect trimmed value
        relayLocked = true                  // lock the field after setting
        relayEnabled = true                 // setting a URL re-enables the relay
        UserDefaults.standard.set(true, forKey: "relayEnabled")
        relay?.stop()
        if !pairing.config.relay.isEmpty {
            relay?.connect(to: pairing.config.relay)
        } else {
            relayConnected = false
        }
    }

    func unlockRelay() { relayLocked = false }

    /// Pause relay delivery without discarding the URL. LAN still works.
    func disableRelay() {
        relayEnabled = false
        UserDefaults.standard.set(false, forKey: "relayEnabled")
        relay?.stop()
        relayConnected = false
    }

    /// Resume relay delivery using the saved URL.
    func enableRelay() {
        relayEnabled = true
        UserDefaults.standard.set(true, forKey: "relayEnabled")
        if !pairing.config.relay.isEmpty {
            relay?.connect(to: pairing.config.relay)
        }
    }

    private func handle(_ env: Envelope) {
        guard env.room == pairing.config.room, let crypto = pairing.crypto else { return }
        guard let plaintext = try? crypto.open(nonceB64: env.nonce, ctB64: env.ct),
              let msg = try? JSONDecoder().decode(OTPMessage.self, from: plaintext) else { return }

        // Once a call is rejected here, ignore its late churn (number/name
        // arriving, or the resulting "missed") so the Reject panel doesn't
        // reappear and the entry stays labelled "Rejected".
        if msg.isCall && rejectedCallIds.contains(msg.id) { return }

        let existing = messages.firstIndex(where: { $0.id == msg.id })
        if let idx = existing {
            // Duplicate delivery. Calls may legitimately update (a late number/
            // name, or a state change on the same call id); SMS/OTP dupes ignored.
            guard msg.isCall else { return }
            messages[idx] = msg
        } else {
            messages.insert(msg, at: 0)
        }
        messageStore.save(messages)
        lastMessage = msg

        if let code = msg.code {
            if existing == nil { Notifications.present(msg); copy(code) }
        } else if msg.isCall {
            processCall(msg)
        } else if msg.isText {
            if existing == nil { setClipboard(msg.text); Notifications.presentText(msg) }
        }
    }

    /// Send a plain text share to the phone (relay reverse channel).
    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let crypto = pairing.crypto else { return }
        let id = UUID().uuidString
        let ts = Date().timeIntervalSince1970 * 1000
        let payload = TextPayload(kind: "text", from: "mac", id: id, ts: ts, text: trimmed)
        if let data = try? JSONEncoder().encode(payload), let sealed = try? crypto.seal(data) {
            relay?.send(Envelope(room: pairing.config.room, nonce: sealed.nonce, ct: sealed.ct))
        }
        // Record locally as a sent item so it shows in the history.
        let mine = OTPMessage(id: id, ts: ts, source: "You → Phone", sender: nil,
                              title: "Sent text", text: trimmed, code: nil,
                              kind: "text", number: nil, name: nil, callState: nil)
        messages.insert(mine, at: 0)
        messageStore.save(messages)
    }

    func setClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func processCall(_ msg: OTPMessage) {
        switch msg.callState {
        case "incoming":
            activeCall = msg                 // keep a persistent Reject in the menu
            Notifications.presentCall(msg)
        case "missed":
            if activeCall?.id == msg.id { activeCall = nil }
            Notifications.presentCall(msg)
        default:                             // answered / ended
            if activeCall?.id == msg.id { activeCall = nil }
        }
    }

    /// Send an encrypted reject command back to the phone via the relay.
    func rejectCall(_ callId: String) {
        guard let crypto = pairing.crypto else { return }
        let cmd = Command(kind: "cmd", cmd: "reject_call", callId: callId)
        if let data = try? JSONEncoder().encode(cmd), let sealed = try? crypto.seal(data) {
            relay?.send(Envelope(room: pairing.config.room, nonce: sealed.nonce, ct: sealed.ct))
        }

        rejectedCallIds.insert(callId)
        if rejectedCallIds.count > 300 { rejectedCallIds.removeAll() }

        // Relabel the history entry as rejected.
        if let idx = messages.firstIndex(where: { $0.id == callId }) {
            let old = messages[idx]
            let display = old.name ?? old.number ?? "Unknown"
            messages[idx] = OTPMessage(
                id: old.id, ts: old.ts, source: old.source, sender: old.sender,
                title: old.title, text: "Rejected call from \(display)", code: nil,
                kind: "call", number: old.number, name: old.name, callState: "rejected"
            )
            messageStore.save(messages)
        }

        if activeCall?.id == callId { activeCall = nil }
    }

    /// Answer the ringing call on the phone (audio stays on the phone).
    func acceptCall(_ callId: String) {
        guard let crypto = pairing.crypto else { return }
        let cmd = Command(kind: "cmd", cmd: "accept_call", callId: callId)
        if let data = try? JSONEncoder().encode(cmd), let sealed = try? crypto.seal(data) {
            relay?.send(Envelope(room: pairing.config.room, nonce: sealed.nonce, ct: sealed.ct))
        }
        // The phone will report "answered", which also clears the panel.
        if activeCall?.id == callId { activeCall = nil }
    }

    func deleteMessages(_ ids: Set<String>) {
        messages.removeAll { ids.contains($0.id) }
        messageStore.save(messages)
    }

    func deleteAllMessages() {
        messages.removeAll()
        messageStore.save(messages)
    }

    func copy(_ code: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(code, forType: .string)

        // Auto-clear after a minute, but only if the user hasn't copied
        // something else in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardClearAfter) {
            if NSPasteboard.general.string(forType: .string) == code {
                NSPasteboard.general.clearContents()
            }
        }
    }
}

// MARK: - App delegate (notification handling)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()
    private var statusController: StatusItemController?
    private var messagesWindow: MessagesWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Single-instance guard: if another copy is already running (e.g. the
        // login-item launch plus a manual launch), quit before adding a second
        // menu-bar icon.
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.hari.otpbridge"
        ).filter { $0.processIdentifier != me }
        if !others.isEmpty { exit(0) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifications.configure(delegate: self)
        model.start()
        let windows = MessagesWindowController(model: model)
        messagesWindow = windows
        statusController = StatusItemController(
            rootView: MenuContent(model: model, openMessages: { windows.show() })
        )

        // Open the Messages window on a direct user launch, but stay quiet when
        // auto-started hidden at login (that isn't a "default" launch).
        let isDefaultLaunch = notification.userInfo?["NSApplicationLaunchIsDefaultLaunchKey"] as? Bool ?? true
        if isDefaultLaunch { windows.show() }
    }

    // Clicking the app in the Dock/Finder while it's already running reopens
    // the Messages window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        messagesWindow?.show()
        return true
    }

    // Show notifications even while the app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Handle the "Copy code" action.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if response.actionIdentifier == Notifications.copyActionID,
           let code = userInfo["code"] as? String {
            Task { @MainActor in self.model.copy(code) }
        } else if response.actionIdentifier == Notifications.rejectActionID,
                  let callId = userInfo["callId"] as? String {
            Task { @MainActor in self.model.rejectCall(callId) }
        } else if response.actionIdentifier == Notifications.acceptActionID,
                  let callId = userInfo["callId"] as? String {
            Task { @MainActor in self.model.acceptCall(callId) }
        }
        completionHandler()
    }
}

// MARK: - Menu bar UI

@main
struct OTPBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // The menu-bar item is managed by StatusItemController (for the animated
    // mascot), so there's no visible window scene.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    var openMessages: () -> Void
    @State private var showQR = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OTP Bridge").font(.headline)

            HStack(spacing: 12) {
                Label(model.lanReady ? "LAN ready" : "LAN off",
                      systemImage: model.lanReady ? "wifi" : "wifi.slash")
                    .foregroundStyle(model.lanReady ? .green : .secondary)
                Label(model.relayConnected ? "Relay up" : "Relay off",
                      systemImage: model.relayConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(model.relayConnected ? .green : .secondary)
            }
            .font(.caption)

            Divider()

            // Relay URL: read-only once set, with a Change button to edit.
            VStack(alignment: .leading, spacing: 4) {
                Text("Relay").font(.caption).foregroundStyle(.secondary)
                if model.relayLocked {
                    HStack {
                        Text(model.relayField.isEmpty ? "None"
                             : (model.relayEnabled ? model.relayField : "\(model.relayField)  (disabled)"))
                            .font(.caption).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(model.relayEnabled ? .secondary : .tertiary)
                        Spacer()
                        Button("Change") { model.unlockRelay() }
                        if !model.relayField.isEmpty {
                            if model.relayEnabled {
                                Button("Disable") { model.disableRelay() }
                            } else {
                                Button("Enable") { model.enableRelay() }
                            }
                        }
                    }
                } else {
                    HStack {
                        TextField("wss:// relay URL (optional)", text: $model.relayField)
                            .textFieldStyle(.roundedBorder)
                        Button("Set") { model.applyRelay() }
                    }
                }
            }

            Button(showQR ? "Hide pairing QR" : "Show pairing QR") { showQR.toggle() }
            if showQR {
                if let img = model.pairing.qrImage() {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 220, height: 220)
                    Text("Scan from the phone app to pair.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Active call controls live in the footer (not the notification).
            if let call = model.activeCall {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("Incoming call", systemImage: "phone.fill")
                        .font(.caption).foregroundStyle(.green)
                    Text(call.name ?? call.number ?? "Unknown")
                        .font(.callout).fontWeight(.semibold)
                    if let num = call.number, call.name != nil {
                        Text(num).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button { model.acceptCall(call.id) } label: {
                            Label("Accept", systemImage: "phone.fill").frame(maxWidth: .infinity)
                        }
                        .tint(.green)
                        Button(role: .destructive) { model.rejectCall(call.id) } label: {
                            Label("Reject", systemImage: "phone.down.fill").frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
            }

            Divider()
            HStack {
                Button {
                    openMessages()
                } label: {
                    Label("Messages", systemImage: "tray.full")
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
