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

    private var lan: LANListener?
    private var relay: RelayClient?
    private var seenIDs: [String] = []          // bounded dedupe window
    private let clipboardClearAfter: TimeInterval = 60
    private let messageStore = MessageStore()

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

        guard !seenIDs.contains(msg.id),
              !messages.contains(where: { $0.id == msg.id }) else { return }  // dedupe
        seenIDs.append(msg.id)
        if seenIDs.count > 200 { seenIDs.removeFirst(seenIDs.count - 200) }

        // Every message (SMS or otherwise) goes into the history list…
        messages.insert(msg, at: 0)
        messageStore.save(messages)
        lastMessage = msg

        // …but only OTPs raise a notification and auto-copy.
        if let code = msg.code {
            Notifications.present(msg)
            copy(code)
        }
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifications.configure(delegate: self)
        model.start()
        let windows = MessagesWindowController(model: model)
        messagesWindow = windows
        statusController = StatusItemController(
            rootView: MenuContent(model: model, openMessages: { windows.show() })
        )
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
        if response.actionIdentifier == Notifications.copyActionID,
           let code = response.notification.request.content.userInfo["code"] as? String {
            Task { @MainActor in self.model.copy(code) }
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
