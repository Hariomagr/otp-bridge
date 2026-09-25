import SwiftUI

/// Email-style history: message list on the left, full content on the right.
struct MessagesView: View {
    @ObservedObject var model: AppModel
    @State private var selection = Set<String>()
    @State private var search = ""
    @State private var showClearConfirm = false

    private var filtered: [OTPMessage] {
        guard !search.isEmpty else { return model.messages }
        let q = search.lowercased()
        return model.messages.filter {
            $0.text.lowercased().contains(q)
                || ($0.sender?.lowercased().contains(q) ?? false)
                || ($0.title?.lowercased().contains(q) ?? false)
                || ($0.code?.contains(q) ?? false)
        }
    }

    private var selectedMessage: OTPMessage? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return model.messages.first(where: { $0.id == id })
    }

    private func deleteSelected() {
        model.deleteMessages(selection)
        selection.removeAll()
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selection) { msg in
                MessageRow(msg: msg).tag(msg.id)
            }
            .onDeleteCommand { if !selection.isEmpty { deleteSelected() } }
            .searchable(text: $search, placement: .sidebar, prompt: "Search messages")
            .navigationTitle("Messages")
            .frame(minWidth: 260)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: {
                        Label(selection.isEmpty ? "Delete" : "Delete (\(selection.count))",
                              systemImage: "trash")
                    }
                    .disabled(selection.isEmpty)

                    Spacer()

                    Button("Clear All") { showClearConfirm = true }
                        .disabled(model.messages.isEmpty)
                }
                .padding(8)
                .background(.bar)
            }
        } detail: {
            if let msg = selectedMessage {
                MessageDetail(msg: msg) { model.copy($0) }
            } else {
                ContentUnavailableView(
                    selection.count > 1 ? "\(selection.count) messages selected" : "No message selected",
                    systemImage: "tray",
                    description: Text(selection.count > 1
                                      ? "Press Delete to remove them."
                                      : "Pick a message from the list.")
                )
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .confirmationDialog("Delete all messages?", isPresented: $showClearConfirm) {
            Button("Delete All", role: .destructive) {
                model.deleteAllMessages()
                selection.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all \(model.messages.count) messages from this Mac.")
        }
    }
}

private struct MessageRow: View {
    let msg: OTPMessage

    var body: some View {
        HStack(spacing: 8) {
            // Dot marks OTP messages.
            Circle()
                .fill(msg.code != nil ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(msg.title ?? msg.sender ?? msg.source)
                        .font(.callout).fontWeight(.semibold).lineLimit(1)
                    Spacer()
                    Text(Date(timeIntervalSince1970: msg.ts / 1000), style: .time)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(msg.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MessageDetail: View {
    let msg: OTPMessage
    let onCopy: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(msg.title ?? msg.sender ?? msg.source)
                            .font(.title3).fontWeight(.bold)
                        if let sender = msg.sender, sender != (msg.title ?? "") {
                            Text(sender).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(msg.source).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(Date(timeIntervalSince1970: msg.ts / 1000)
                        .formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let code = msg.code {
                    HStack(spacing: 12) {
                        Text(code)
                            .font(.system(.title, design: .monospaced)).fontWeight(.bold)
                        Button {
                            onCopy(code)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12)))
                }

                Text(msg.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(20)
        }
    }
}
