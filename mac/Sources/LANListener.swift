import Foundation
import Network

/// Advertises `_otpbridge._tcp` via Bonjour and accepts newline-delimited JSON
/// envelopes from the phone when both are on the same Wi-Fi.
final class LANListener {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "otpbridge.lan")
    private let onEnvelope: (Envelope) -> Void
    private let onState: (Bool) -> Void

    init(onEnvelope: @escaping (Envelope) -> Void, onState: @escaping (Bool) -> Void) {
        self.onEnvelope = onEnvelope
        self.onState = onState
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let listener = try NWListener(using: params)
            listener.service = NWListener.Service(name: nil, type: "_otpbridge._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.onState(true)
                case .failed, .cancelled: self?.onState(false)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            onState(false)
        }
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(on: conn, buffer: Data())
    }

    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data, !data.isEmpty { buf.append(data) }

            // Split on newlines; each line is one JSON envelope.
            while let nl = buf.firstIndex(of: 0x0A) {
                let line = buf[buf.startIndex..<nl]
                buf.removeSubrange(buf.startIndex...nl)
                if let env = try? JSONDecoder().decode(Envelope.self, from: Data(line)) {
                    self.onEnvelope(env)
                }
            }

            if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(on: conn, buffer: buf)
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
