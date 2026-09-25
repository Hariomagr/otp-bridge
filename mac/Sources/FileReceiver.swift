import Foundation
import Network

/// Metadata sent as the first frame of a transfer.
struct FileMeta: Codable {
    let id: String
    let name: String
    let mime: String
    let size: Int
}

/// Receives files from the phone over LAN. Advertises `_obfmac._tcp` via
/// Bonjour; each connection carries one file as length-prefixed encrypted
/// frames: [4-byte BE length][1-byte type][12-byte nonce][ciphertext||tag].
/// type 0 = header (FileMeta JSON), 1 = chunk (raw bytes), 2 = end.
final class FileReceiver {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "otpbridge.file.rx")
    private let cryptoProvider: () -> Crypto?
    private let onFile: (String, URL) -> Void
    private var sessions = [ObjectIdentifier: FileRxSession]()   // retain in-flight transfers

    init(cryptoProvider: @escaping () -> Crypto?, onFile: @escaping (String, URL) -> Void) {
        self.cryptoProvider = cryptoProvider
        self.onFile = onFile
    }

    func start() {
        do {
            // includePeerToPeer matches the LAN listener; the `_obfmac._tcp`
            // type must also be declared in Info.plist's NSBonjourServices or
            // advertising fails with NoAuth.
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let l = try NWListener(using: params)
            l.service = NWListener.Service(name: nil, type: "_obfmac._tcp")
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                let session = FileRxSession(conn: conn, crypto: self.cryptoProvider(), onFile: self.onFile)
                let key = ObjectIdentifier(session)
                session.onDone = { [weak self] in self?.queue.async { self?.sessions[key] = nil } }
                self.queue.async { self.sessions[key] = session }   // retain until done
                conn.start(queue: self.queue)
                session.read()
            }
            l.start(queue: queue)
            listener = l
        } catch {
            // Best-effort; phone→Mac files just won't work over LAN.
        }
    }
}

private final class FileRxSession {
    private let conn: NWConnection
    private let crypto: Crypto?
    private let onFile: (String, URL) -> Void
    var onDone: (() -> Void)?

    private var buffer = [UInt8]()
    private var handle: FileHandle?
    private var tempURL: URL?
    private var name = "file"

    init(conn: NWConnection, crypto: Crypto?, onFile: @escaping (String, URL) -> Void) {
        self.conn = conn
        self.crypto = crypto
        self.onFile = onFile
    }

    func read() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let d = data, !d.isEmpty { self.buffer.append(contentsOf: d) }
            self.parse()
            if isComplete || error != nil {
                self.handle?.closeFile()
                self.conn.cancel()
                self.onDone?()
            } else {
                self.read()
            }
        }
    }

    private func parse() {
        while buffer.count >= 4 {
            let len = (Int(buffer[0]) << 24) | (Int(buffer[1]) << 16) | (Int(buffer[2]) << 8) | Int(buffer[3])
            guard len > 0, buffer.count >= 4 + len else { break }
            let frame = Array(buffer[4 ..< 4 + len])
            buffer.removeFirst(4 + len)
            handle(frame: frame)
        }
    }

    private func handle(frame: [UInt8]) {
        guard frame.count >= 13, let crypto else { return }
        let type = frame[0]
        let nonce = Data(frame[1 ..< 13])
        let ctTag = Data(frame[13...])
        guard let plaintext = try? crypto.openRaw(nonce: nonce, ctTag: ctTag) else { return }

        switch type {
        case 0: // header
            if let meta = try? JSONDecoder().decode(FileMeta.self, from: plaintext) {
                name = meta.name.isEmpty ? "file" : meta.name
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                FileManager.default.createFile(atPath: tmp.path, contents: nil)
                tempURL = tmp
                handle = try? FileHandle(forWritingTo: tmp)
            }
        case 1: // chunk
            if let h = handle { try? h.write(contentsOf: plaintext) }
        case 2: // end
            handle?.closeFile()
            handle = nil
            if let tmp = tempURL { save(tmp) }
        default:
            break
        }
    }

    private func save(_ tmp: URL) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var dest = downloads.appendingPathComponent(name)
        let base = dest.deletingPathExtension().lastPathComponent
        let ext = dest.pathExtension
        var i = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let candidate = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            dest = downloads.appendingPathComponent(candidate)
            i += 1
        }
        do {
            try FileManager.default.moveItem(at: tmp, to: dest)
            onFile(name, dest)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}
