import Foundation

/// WebSocket client for the relay fallback. Joins the room and forwards every
/// `msg` frame's envelope to the router. Auto-reconnects with backoff.
final class RelayClient: NSObject {
    private let room: String
    private let onEnvelope: (Envelope) -> Void
    private let onState: (Bool) -> Void

    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var relayURL: URL?
    private var reconnectDelay: TimeInterval = 1
    private var stopped = false

    init(room: String, onEnvelope: @escaping (Envelope) -> Void, onState: @escaping (Bool) -> Void) {
        self.room = room
        self.onEnvelope = onEnvelope
        self.onState = onState
        super.init()
        self.session = URLSession(configuration: .default)
    }

    func connect(to urlString: String) {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            onState(false)
            return
        }
        relayURL = url
        stopped = false
        openSocket()
    }

    private func openSocket() {
        guard let url = relayURL, !stopped else { return }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        sendJoin()
        receive()
    }

    private func sendJoin() {
        let join = #"{"type":"join","room":"\#(room)"}"#
        task?.send(.string(join)) { [weak self] error in
            self?.onState(error == nil)
        }
    }

    /// Send an encrypted envelope to the room (reverse channel: Mac -> phone).
    func send(_ env: Envelope) {
        guard let data = try? JSONEncoder().encode(
            ["type": "msg", "room": env.room, "nonce": env.nonce, "ct": env.ct]
        ), let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let env = try? JSONDecoder().decode(Envelope.self, from: data),
                   !env.ct.isEmpty {
                    self.onEnvelope(env)
                }
                self.receive()
            case .failure:
                self.onState(false)
                self.scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.openSocket()
        }
    }

    func stop() {
        stopped = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}
