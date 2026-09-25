import Foundation
import Network

/// Sends files from the Mac to the phone over LAN. Browses for the phone's
/// `_obfand._tcp` service, connects, and streams length-prefixed encrypted
/// frames matching the phone's FileServer:
///   [4-byte BE length][1-byte type][nonce(12)||ct||tag]
///   type 0 = header (FileMeta JSON), 1 = chunk, 2 = end.
final class FileSender {
    private let cryptoProvider: () -> Crypto?
    private let queue = DispatchQueue(label: "otpbridge.file.tx")
    private let chunkSize = 64 * 1024

    init(cryptoProvider: @escaping () -> Crypto?) {
        self.cryptoProvider = cryptoProvider
    }

    /// Send files sequentially. Completion is called on the main queue with the
    /// count sent and whether the phone was found at all. Chains via callbacks
    /// (no blocking) since the connection's handlers run on `queue`.
    func send(_ urls: [URL], completion: @escaping (_ sent: Int, _ found: Bool) -> Void) {
        resolvePhone { [weak self] endpoint in
            guard let self else { return }
            guard let endpoint else {
                DispatchQueue.main.async { completion(0, false) }
                return
            }
            self.sendNext(urls, index: 0, to: endpoint, sent: 0, completion: completion)
        }
    }

    private func sendNext(_ urls: [URL], index: Int, to endpoint: NWEndpoint,
                          sent: Int, completion: @escaping (Int, Bool) -> Void) {
        if index >= urls.count {
            DispatchQueue.main.async { completion(sent, true) }
            return
        }
        sendOne(urls[index], to: endpoint) { [weak self] ok in
            guard let self else { return }
            self.sendNext(urls, index: index + 1, to: endpoint,
                          sent: sent + (ok ? 1 : 0), completion: completion)
        }
    }

    // MARK: - Bonjour resolve

    private var browser: NWBrowser?

    private func resolvePhone(_ completion: @escaping (NWEndpoint?) -> Void) {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_obfand._tcp", domain: nil), using: params)
        self.browser = browser
        var finished = false
        let finish: (NWEndpoint?) -> Void = { ep in
            if finished { return }
            finished = true
            browser.cancel()
            completion(ep)
        }
        browser.browseResultsChangedHandler = { results, _ in
            if let first = results.first { finish(first.endpoint) }
        }
        browser.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 4) { finish(nil) }   // discovery timeout
    }

    // MARK: - Send one file

    private func sendOne(_ url: URL, to endpoint: NWEndpoint, completion: @escaping (Bool) -> Void) {
        guard let crypto = cryptoProvider(),
              let handle = try? FileHandle(forReadingFrom: url) else { completion(false); return }

        var finished = false
        let finish: (Bool) -> Void = { ok in
            if finished { return }
            finished = true
            completion(ok)
        }

        let conn = NWConnection(to: endpoint, using: {
            let p = NWParameters.tcp; p.includePeerToPeer = true; return p
        }())

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let meta = FileMeta(id: UUID().uuidString, name: url.lastPathComponent,
                            mime: "application/octet-stream", size: size ?? 0)

        func frame(type: UInt8, _ payload: Data) -> Data? {
            guard let sealed = try? crypto.sealRaw(payload) else { return nil }
            var body = Data([type]); body.append(sealed)
            var len = UInt32(body.count).bigEndian
            var out = Data(bytes: &len, count: 4); out.append(body)
            return out
        }

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.queue.async {
                    guard let header = try? JSONEncoder().encode(meta),
                          let hFrame = frame(type: 0, header) else {
                        conn.cancel(); finish(false); return
                    }
                    conn.send(content: hFrame, completion: .contentProcessed { _ in })

                    while true {
                        let chunk = handle.readData(ofLength: self.chunkSize)
                        if chunk.isEmpty { break }
                        if let f = frame(type: 1, chunk) {
                            conn.send(content: f, completion: .contentProcessed { _ in })
                        }
                    }
                    try? handle.close()
                    if let endFrame = frame(type: 2, Data()) {
                        conn.send(content: endFrame, completion: .contentProcessed { _ in
                            finish(true)          // report success once the end frame flushed
                            conn.cancel()
                        })
                    } else {
                        finish(true); conn.cancel()
                    }
                }
            case .failed, .cancelled:
                try? handle.close()
                finish(false)
            default:
                break
            }
        }
        conn.start(queue: queue)
    }
}
