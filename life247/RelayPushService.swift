//
//  RelayPushService.swift
//  life247
//
//  Relays life247 alerts to ntfy.sh so the other person is notified even when the
//  app is force-quit. The device that *owns* an event POSTs it to a shared topic
//  that both people subscribe to in the free ntfy app — no Apple Developer
//  account, no APNs key, and no server required. Delivery is handled by ntfy
//  (which has its own real push entitlement), not by life247.
//

import Foundation

final class RelayPushService {
    static let shared = RelayPushService()

    /// Display name of the operator signed in on this device (e.g. "Noah"). Set at
    /// login so every relayed alert is clearly attributed to whoever triggered it.
    var currentUserName: String?

    /// ntfy notification priority. Maps to the `Priority` header it expects.
    enum Priority: String {
        case low
        case `default`
        case high
        case urgent
    }

    private let endpoint = "https://ntfy.sh"

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private init() {}

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettingsKeys.relayPushEnabled)
    }

    private var topic: String {
        (UserDefaults.standard.string(forKey: AppSettingsKeys.relayTopic) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var senderName: String {
        let name = currentUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "life247" : name
    }

    /// "Noah: " — used to attribute non-chat alerts to their sender.
    private var prefix: String { "\(senderName): " }

    // MARK: - Event relays

    func relaySOS() {
        send(title: "\(prefix)SOS",
             body: "needs help — open life247 to see their location.",
             priority: .urgent,
             tags: ["rotating_light"])
    }

    func relayChat(_ text: String) {
        send(title: senderName,
             body: text,
             priority: .high,
             tags: ["speech_balloon"])
    }

    func relayLowBattery(percent: Int) {
        send(title: "\(prefix)Low battery",
             body: "battery at \(percent)%.",
             priority: .high,
             tags: ["warning", "battery"])
    }

    func relayPlaceArrival(_ placeName: String) {
        send(title: "\(prefix)Arrived",
             body: "arrived at \(placeName).",
             priority: .default,
             tags: ["round_pushpin"])
    }

    func relayPlaceDeparture(_ placeName: String) {
        send(title: "\(prefix)Left",
             body: "left \(placeName).",
             priority: .default,
             tags: ["round_pushpin"])
    }

    func relayTripComplete(duration: TimeInterval, topSpeedMetersPerSecond: Double) {
        let summary = "\(UnitFormatter.durationString(seconds: duration)) trip, top speed \(UnitFormatter.speedString(metersPerSecond: topSpeedMetersPerSecond))."
        send(title: "\(prefix)Trip complete",
             body: summary,
             priority: .default,
             tags: ["car"])
    }

    // MARK: - Core send

    func send(title: String, body: String, priority: Priority = .default, tags: [String] = []) {
        guard isEnabled else { return }
        let topic = self.topic
        guard !topic.isEmpty,
              let escapedTopic = topic.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(endpoint)/\(escapedTopic)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.asciiHeader(title), forHTTPHeaderField: "Title")
        request.setValue(priority.rawValue, forHTTPHeaderField: "Priority")
        if !tags.isEmpty {
            request.setValue(tags.joined(separator: ","), forHTTPHeaderField: "Tags")
        }
        request.httpBody = body.data(using: .utf8)
        session.dataTask(with: request).resume()
    }

    /// HTTP header values must be ASCII, so emoji/diacritics are dropped from the
    /// title and carried via the `Tags` header (rendered as icons by ntfy) instead.
    private static func asciiHeader(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter { $0.isASCII }))
    }
}
