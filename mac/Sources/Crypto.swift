import Foundation
import CryptoKit

enum CryptoError: Error { case badKey, badMessage }

/// AES-256-GCM with the pre-shared pairing key. `ct` on the wire is
/// ciphertext followed by the 16-byte tag. AAD is the room string's bytes.
struct Crypto {
    private let key: SymmetricKey
    private let roomAAD: Data

    init(keyBase64: String, room: String) throws {
        guard let kd = Data(base64Encoded: keyBase64), kd.count == 32 else {
            throw CryptoError.badKey
        }
        self.key = SymmetricKey(data: kd)
        self.roomAAD = Data(room.utf8)
    }

    func open(nonceB64: String, ctB64: String) throws -> Data {
        guard let nonceData = Data(base64Encoded: nonceB64),
              let ctFull = Data(base64Encoded: ctB64),
              ctFull.count > 16 else { throw CryptoError.badMessage }
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let tag = ctFull.suffix(16)
        let ct = ctFull.prefix(ctFull.count - 16)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        return try AES.GCM.open(box, using: key, authenticating: roomAAD)
    }

    /// Kept for tests and future Mac->phone messaging.
    func seal(_ plaintext: Data) throws -> (nonce: String, ct: String) {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: roomAAD)
        return (Data(box.nonce).base64EncodedString(),
                (box.ciphertext + box.tag).base64EncodedString())
    }

    // Raw binary variants for file-transfer frames (avoid base64 overhead).

    /// Returns nonce(12) || ciphertext || tag(16).
    func sealRaw(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: roomAAD)
        return Data(box.nonce) + box.ciphertext + box.tag
    }

    func openRaw(nonce: Data, ctTag: Data) throws -> Data {
        guard ctTag.count >= 16 else { throw CryptoError.badMessage }
        let sealedNonce = try AES.GCM.Nonce(data: nonce)
        let tag = ctTag.suffix(16)
        let ct = ctTag.prefix(ctTag.count - 16)
        let box = try AES.GCM.SealedBox(nonce: sealedNonce, ciphertext: ct, tag: tag)
        return try AES.GCM.open(box, using: key, authenticating: roomAAD)
    }
}
