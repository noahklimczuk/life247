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

    /// Lowercased username of the operator signed in on this device, if any.
    private(set) var currentUsername: String?

    private let circleID = "main"
    private let session = URLSession(configuration: .default)
    private let publishInterval: TimeInterval = 5.0
    private let pollInterval: TimeInterval = 5.0

    private var memberID = ""
    private var memberName = ""
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
    }

    // MARK: - Publish

    private func publishSelf() {
        guard let base = databaseURL,
              let username = currentUsername,
              let coordinate = BackgroundTrackingEngine.shared.liveLocation,
              let url = URL(string: "\(base)/circles/\(circleID)/members/\(username).json") else { return }

        let payload: [String: Any] = [
            "id": memberID,
            "name": memberName,
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "batteryPercentage": BackgroundTrackingEngine.batteryPercentage(from: UIDevice.current.batteryLevel),
            "currentSpeed": 0.0,
            "activity": TrackedUserActivity.stationary.rawValue,
            "updatedAt": Date().timeIntervalSince1970
        ]

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
                  let roster = object as? [String: [String: Any]] else { return }

            let parsed = roster.values.compactMap { Self.decodeMember($0) }
            DispatchQueue.main.async {
                self.members = parsed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }.resume()
    }

    private static func decodeMember(_ dict: [String: Any]) -> UserState? {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String,
              let latitude = (dict["latitude"] as? NSNumber)?.doubleValue,
              let longitude = (dict["longitude"] as? NSNumber)?.doubleValue else { return nil }

        let battery = (dict["batteryPercentage"] as? NSNumber)?.intValue ?? 100
        let speed = (dict["currentSpeed"] as? NSNumber)?.doubleValue ?? 0.0
        let activity = (dict["activity"] as? String).flatMap { TrackedUserActivity(rawValue: $0) } ?? .stationary
        let updatedAt = (dict["updatedAt"] as? NSNumber)?.doubleValue

        return UserState(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            batteryPercentage: battery,
            currentSpeed: speed,
            activity: activity,
            atLocationSince: updatedAt.map { Date(timeIntervalSince1970: $0) } ?? Date()
        )
    }
}
