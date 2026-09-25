import Foundation

/// What crosses the wire on both LAN and relay. Opaque to the relay.
struct Envelope: Codable {
    let room: String
    let nonce: String
    let ct: String
}

/// The decrypted payload the phone sends.
struct OTPMessage: Codable, Identifiable {
    let id: String
    let ts: Double
    let source: String
    let sender: String?
    let title: String?
    let text: String
    let code: String?
    var kind: String?        // "sms" | "call" | "text" | "file"
    var number: String?      // call
    var name: String?        // call
    var callState: String?   // "incoming" | "missed"
    var fileName: String? = nil    // file
    var localPath: String? = nil   // file: where it was saved on this Mac

    var isCall: Bool { kind == "call" }
    var isIncomingCall: Bool { kind == "call" && callState == "incoming" }
    var isText: Bool { kind == "text" }
    var isFile: Bool { kind == "file" }
}

/// A plain text share from the Mac to the phone, encrypted like everything else.
/// `from: "mac"` lets the phone ignore its own relayed texts (no echo).
struct TextPayload: Codable {
    let kind: String   // "text"
    let from: String   // "mac"
    let id: String
    let ts: Double
    let text: String
}

/// Mac -> phone command (reject a ringing call), encrypted like everything else.
struct Command: Codable {
    let kind: String
    let cmd: String
    let callId: String
}

/// Everything the phone needs to pair, encoded into the QR code.
struct PairingConfig: Codable {
    let v: Int
    let key: String     // standard base64, 32 bytes
    let room: String    // hex, 16 bytes
    let relay: String   // wss:// URL (may be empty until user sets it)
    let name: String
}
