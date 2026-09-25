import Foundation
import AppKit
import CoreImage
import Security

/// Owns the persistent pairing config (key/room/relay/name) and renders the QR.
/// Personal-use: the key is generated once on the Mac and lives in a JSON file
/// in Application Support.
@MainActor
final class PairingStore: ObservableObject {
    @Published private(set) var config: PairingConfig

    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OTPBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("pairing.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(PairingConfig.self, from: data) {
            self.config = loaded
        } else {
            self.config = PairingStore.generate()
            save()
        }
    }

    private static func generate() -> PairingConfig {
        PairingConfig(
            v: 1,
            key: randomBytes(32).base64EncodedString(),
            room: randomBytes(16).map { String(format: "%02x", $0) }.joined(),
            relay: "",
            name: Host.current().localizedName ?? "Mac"
        )
    }

    private static func randomBytes(_ n: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes)
    }

    func setRelay(_ url: String) {
        config = PairingConfig(v: config.v, key: config.key, room: config.room,
                               relay: url.trimmingCharacters(in: .whitespacesAndNewlines),
                               name: config.name)
        save()
    }

    var crypto: Crypto? { try? Crypto(keyBase64: config.key, room: config.room) }

    /// The JSON the phone scans.
    var qrPayload: String {
        (try? String(data: JSONEncoder().encode(config), encoding: .utf8) ?? "") ?? ""
    }

    func qrImage(side: CGFloat = 240) -> NSImage? {
        let data = Data(qrPayload.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
