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
    var kind: String?        // "sms" | "call" (nil == sms)
    var number: String?      // call
    var name: String?        // call
    var callState: String?   // "incoming" | "missed"

    var isCall: Bool { kind == "call" }
    var isIncomingCall: Bool { kind == "call" && callState == "incoming" }
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
