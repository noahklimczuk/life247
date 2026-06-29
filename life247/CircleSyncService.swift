//
//  CircleSyncService.swift
//  life247
//
//  Lightweight cross-device location sharing backed by Firebase Realtime
//  Database. Uses the database's REST API over URLSession so it needs no SDK,
//  Swift Package, or .pbxproj changes — only a database URL configured via the
//  `FirebaseDatabaseURL` Info.plist key.
//

import Foundation
import CoreLocation
import Combine
import UIKit

/// Publishes the signed-in operator's live telemetry to a shared "circle" and
/// keeps an up-to-date roster of every other member by polling the database.
final class CircleSyncService: ObservableObject {
    static let shared = CircleSyncService()

    /// Every known member of the circle (including the current operator), most
    /// recently updated location/battery first resolved from the database.
    @Published var members: [UserState] = []

    /// When true, this device is broadcasting an active SOS to the circle.
    @Published var isBroadcastingSOS = false

    /// Lowercased username of the operator signed in on this device, if any.
    private(set) var currentUsername: String?

    // Per-member previous state used to fire one-shot transition alerts.
    private var previousPlaceIdByMember: [String: UUID] = [:]
    private var previousBatteryByMember: [String: Int] = [:]
    private var previousSOSByMember: [String: Bool] = [:]
    private var didLoadInitialRoster = false

    // Previous battery level of this device, used to relay a one-shot low-battery push.
    private var previousSelfBattery: Int?

    private let lowBatteryThreshold = 20

    private let circleID = "main"

    /// No caching: a live roster must never be served a stale cached response,
    /// so each poll hits the database directly.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private let publishInterval: TimeInterval = 5.0
    private let pollInterval: TimeInterval = 5.0

    private var memberID = ""
    private var memberName = ""
    private var memberAvatar: String?
    private var publishTimer: Timer?
    private var pollTimer: Timer?

    private init() {}

    /// Configured Realtime Database base URL, e.g.
    /// `https://life247-xxxx-default-rtdb.firebaseio.com`. Empty until the user
    /// pastes it into Info.plist, in which case the service no-ops gracefully.
    private var databaseURL: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FirebaseDatabaseURL") as? String else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Lifecycle

    /// Begins sharing this operator's location and polling the rest of the circle.
    func start(id: String, name: String, username: String) {
        memberID = id
        memberName = name
        currentUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        publishTimer?.invalidate()
        pollTimer?.invalidate()

        previousPlaceIdByMember = [:]
        previousBatteryByMember = [:]
        previousSOSByMember = [:]
        didLoadInitialRoster = false

        publishSelf()
        fetchMembers()

        publishTimer = Timer.scheduledTimer(withTimeInterval: publishInterval, repeats: true) { [weak self] _ in
            self?.publishSelf()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.fetchMembers()
        }
    }

    /// Stops publishing this operator's position. The last-known node is left in
    /// the database so other members still see this operator on their map.
    func stop() {
        publishTimer?.invalidate(); publishTimer = nil
        pollTimer?.invalidate(); pollTimer = nil
        currentUsername = nil
        isBroadcastingSOS = false
        didLoadInitialRoster = false
    }

    /// Updates this operator's broadcast display name and re-publishes it so the
    /// rest of the circle picks up the change on their next poll.
    func updateDisplayName(_ name: String) {
        memberName = name
        publishSelf()
    }

    /// Updates this operator's broadcast profile picture (base64 JPEG, nil to clear).
    func updateAvatar(_ base64: String?) {
        memberAvatar = base64
        publishSelf()
    }

    /// Toggles this device's SOS broadcast and pushes it out immediately.
    func setSOS(_ active: Bool) {
        isBroadcastingSOS = active
        if active { RelayPushService.shared.relaySOS() }
        publishSelf()
    }

    // MARK: - Publish

    private func publishSelf() {
        guard UserDefaults.standard.bool(forKey: AppSettingsKeys.shareLocation) else { return }
        guard let base = databaseURL,
              let username = currentUsername,
              let coordinate = BackgroundTrackingEngine.shared.liveLocation,
              let url = URL(string: "\(base)/circles/\(circleID)/members/\(username).json") else { return }

        let speed = max(0, BackgroundTrackingEngine.shared.liveSpeed)
        let state = UIDevice.current.batteryState
        let isCharging = (state == .charging || state == .full)
        let battery = BackgroundTrackingEngine.batteryPercentage(from: UIDevice.current.batteryLevel)

        // Relay this device's own low-battery alert once, as it crosses the threshold.
        if let previous = previousSelfBattery, previous >= lowBatteryThreshold,
           battery < lowBatteryThreshold, !isCharging {
            RelayPushService.shared.relayLowBattery(percent: battery)
        }
        previousSelfBattery = battery

        var payload: [String: Any] = [
            "id": memberID,
            "name": memberName,
            "username": username,
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "batteryPercentage": battery,
            "isCharging": isCharging,
            "sos": isBroadcastingSOS,
            "currentSpeed": speed,
            "activity": Self.activity(forSpeedMetersPerSecond: speed).rawValue,
            "updatedAt": Date().timeIntervalSince1970,
            "atLocationSince": BackgroundTrackingEngine.shared.atLocationSince.timeIntervalSince1970
        ]
        if let memberAvatar { payload["avatar"] = memberAvatar }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request).resume()
    }

    // MARK: - Poll

    private func fetchMembers() {
        guard let base = databaseURL,
              let url = URL(string: "\(base)/circles/\(circleID)/members.json") else { return }

        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  !data.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let roster = object as? [String: Any] else { return }

            let parsed = roster.compactMap { key, value in
                (value as? [String: Any]).flatMap { Self.decodeMember($0, fallbackUsername: key) }
            }
            DispatchQueue.main.async {
                let sorted = parsed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.detectAndAlertTransitions(for: sorted)
                self.members = sorted
            }
        }.resume()
    }

    // MARK: - Presence & alerts

    /// The saved place a member is currently inside, if any.
    func place(for member: UserState) -> GeofenceZone? {
        containingZone(latitude: member.latitude, longitude: member.longitude)
    }

    private func containingZone(latitude: Double, longitude: Double) -> GeofenceZone? {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        return BackgroundTrackingEngine.shared.activeGeofences.first { zone in
            here.distance(from: CLLocation(latitude: zone.latitude, longitude: zone.longitude)) <= zone.radius
        }
    }

    /// Compares the freshly fetched roster against the previous snapshot and fires
    /// one-shot local notifications for the partner's place/battery/SOS changes.
    /// The first roster after sign-in only seeds state so it stays silent.
    private func detectAndAlertTransitions(for roster: [UserState]) {
        defer { didLoadInitialRoster = true }

        for member in roster {
            let key = member.username
            if let me = currentUsername, key == me { continue }

            let zone = containingZone(latitude: member.latitude, longitude: member.longitude)
            let previousZoneID = previousPlaceIdByMember[key]
            let previousBattery = previousBatteryByMember[key]
            let previousSOS = previousSOSByMember[key] ?? false

            if didLoadInitialRoster {
                // Place arrival / departure.
                if let zone, previousZoneID != zone.id {
                    NotificationManager.shared.post(title: "\(member.name) arrived",
                                                    body: "\(member.name) is at \(zone.name)",
                                                    category: .place)
                } else if zone == nil, let previousZoneID,
                          let previousZone = BackgroundTrackingEngine.shared.activeGeofences.first(where: { $0.id == previousZoneID }) {
                    NotificationManager.shared.post(title: "\(member.name) left",
                                                    body: "\(member.name) left \(previousZone.name)",
                                                    category: .place)
                }

                // Low battery (only when crossing the threshold downward).
                if let previousBattery, previousBattery >= lowBatteryThreshold,
                   member.batteryPercentage < lowBatteryThreshold, !member.isCharging {
                    NotificationManager.shared.post(title: "\(member.name)'s phone is low",
                                                    body: "Battery at \(member.batteryPercentage)%",
                                                    category: .battery)
                }

                // SOS raised → persistent, ringer-bypassing alert. Cleared when resolved.
                if member.isSOS, !previousSOS {
                    NotificationManager.shared.postSOS(title: "🆘 \(member.name) needs help",
                                                       body: "\(member.name) triggered an SOS. Open life247 to see their location.")
                } else if !member.isSOS, previousSOS {
                    NotificationManager.shared.clearSOS()
                }
            }

            previousPlaceIdByMember[key] = zone?.id
            previousBatteryByMember[key] = member.batteryPercentage
            previousSOSByMember[key] = member.isSOS
        }
    }

    /// Maps a raw speed (m/s) to a coarse activity classification.
    private static func activity(forSpeedMetersPerSecond speed: Double) -> TrackedUserActivity {
        let kmh = speed * 3.6
        if kmh > 12 { return .driving }
        if kmh > 1.5 { return .walking }
        return .stationary
    }

    private nonisolated static func decodeMember(_ dict: [String: Any], fallbackUsername: String) -> UserState? {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String,
              let latitude = (dict["latitude"] as? NSNumber)?.doubleValue,
              let longitude = (dict["longitude"] as? NSNumber)?.doubleValue,
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) else { return nil }

        let battery = (dict["batteryPercentage"] as? NSNumber)?.intValue ?? 100
        let isCharging = (dict["isCharging"] as? NSNumber)?.boolValue ?? false
        let isSOS = (dict["sos"] as? NSNumber)?.boolValue ?? false
        let speed = (dict["currentSpeed"] as? NSNumber)?.doubleValue ?? 0.0
        let activity = (dict["activity"] as? String).flatMap { TrackedUserActivity(rawValue: $0) } ?? .stationary
        let updatedAt = (dict["updatedAt"] as? NSNumber)?.doubleValue
        let atLocationSinceTs = (dict["atLocationSince"] as? NSNumber)?.doubleValue
        let username = (dict["username"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackUsername
        let avatar = (dict["avatar"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        return UserState(
            id: id,
            name: name,
            username: username.lowercased(),
            latitude: latitude,
            longitude: longitude,
            batteryPercentage: battery,
            currentSpeed: speed,
            activity: activity,
            isCharging: isCharging,
            isSOS: isSOS,
            avatarBase64: avatar,
            atLocationSince: atLocationSinceTs.map { Date(timeIntervalSince1970: $0) }
                ?? updatedAt.map { Date(timeIntervalSince1970: $0) }
                ?? Date(),
            lastUpdated: updatedAt.map { Date(timeIntervalSince1970: $0) } ?? Date()
        )
    }
}
