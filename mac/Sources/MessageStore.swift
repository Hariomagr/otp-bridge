import Foundation

/// Local persistence for received message history (newest first). Stored as a
/// JSON file in Application Support. Bounded so it doesn't grow forever.
@MainActor
final class MessageStore {
    private let fileURL: URL
    private let limit = 500

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OTPBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("messages.json")
    }

    func load() -> [OTPMessage] {
        guard let data = try? Data(contentsOf: fileURL),
              let msgs = try? JSONDecoder().decode([OTPMessage].self, from: data) else { return [] }
        return msgs
    }

    func save(_ messages: [OTPMessage]) {
        let trimmed = Array(messages.prefix(limit))
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
