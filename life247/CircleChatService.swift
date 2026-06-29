//
//  CircleChatService.swift
//  life247
//
//  In-circle messaging over the Firebase Realtime Database REST API (SDK-free).
//  Messages live at /circles/main/messages; this service POSTs new messages and
//  polls for the shared thread, firing a local notification for incoming ones.
//

import Foundation
import Combine

final class CircleChatService: ObservableObject {
    static let shared = CircleChatService()

    @Published private(set) var messages: [ChatMessage] = []

    /// Set by the chat screen so incoming messages don't also fire a notification
    /// while the user is already reading the thread.
    var isViewingChat = false

    private let circleID = "main"
    private let pollInterval: TimeInterval = 4.0

    private var senderId = ""
    private var senderName = ""
    private var pollTimer: Timer?
    private var lastSeenTimestamp: Double = Date().timeIntervalSince1970
    private var didLoadInitial = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private init() {}

    private var databaseURL: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FirebaseDatabaseURL") as? String else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed.isEmpty ? nil : trimmed
    }

    private var messagesURL: URL? {
        guard let base = databaseURL else { return nil }
        return URL(string: "\(base)/circles/\(circleID)/messages.json")
    }

    // MARK: - Lifecycle

    func start(senderId: String, senderName: String) {
        self.senderId = senderId.lowercased()
        self.senderName = senderName
        didLoadInitial = false
        lastSeenTimestamp = Date().timeIntervalSince1970

        pollTimer?.invalidate()
        fetchMessages()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.fetchMessages()
        }
    }

    func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        messages = []
        didLoadInitial = false
    }

    // MARK: - Send

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = messagesURL else { return }

        let now = Date().timeIntervalSince1970
        let payload: [String: Any] = [
            "senderId": senderId,
            "senderName": senderName,
            "text": trimmed,
            "ts": now
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        // Relay outgoing messages so the other person is alerted even if their
        // app is force-quit (check-ins post here too, so they relay as well).
        RelayPushService.shared.relayChat(trimmed)

        // Optimistic local echo so the sender sees it immediately.
        let optimistic = ChatMessage(id: UUID().uuidString, senderId: senderId, senderName: senderName, text: trimmed, timestamp: Date(timeIntervalSince1970: now))
        DispatchQueue.main.async {
            self.messages.append(optimistic)
            self.lastSeenTimestamp = max(self.lastSeenTimestamp, now)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request) { [weak self] _, _, _ in
            self?.fetchMessages()
        }.resume()
    }

    // MARK: - Poll

    private func fetchMessages() {
        guard let url = messagesURL else { return }

        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data, !data.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any] else { return }

            let parsed = dict.compactMap { key, value -> ChatMessage? in
                guard let entry = value as? [String: Any] else { return nil }
                return Self.decode(id: key, entry)
            }
            .sorted { $0.timestamp < $1.timestamp }

            DispatchQueue.main.async {
                self.handleFetched(parsed)
            }
        }.resume()
    }

    private func handleFetched(_ fetched: [ChatMessage]) {
        let incoming = fetched.filter { $0.senderId != senderId && $0.timestamp.timeIntervalSince1970 > lastSeenTimestamp }

        messages = fetched
        if let newestTs = fetched.last?.timestamp.timeIntervalSince1970 {
            lastSeenTimestamp = max(lastSeenTimestamp, newestTs)
        }

        if didLoadInitial, !isViewingChat {
            for message in incoming {
                NotificationManager.shared.post(title: message.senderName, body: message.text, category: .chat)
            }
        }
        didLoadInitial = true
    }

    private static func decode(id: String, _ dict: [String: Any]) -> ChatMessage? {
        guard let senderId = dict["senderId"] as? String,
              let text = dict["text"] as? String,
              let ts = (dict["ts"] as? NSNumber)?.doubleValue else { return nil }
        let name = dict["senderName"] as? String ?? senderId.capitalized
        return ChatMessage(
            id: id,
            senderId: senderId,
            senderName: name,
            text: text,
            timestamp: Date(timeIntervalSince1970: ts)
        )
    }
}
