//
//  PlacesSyncService.swift
//  life247
//
//  Syncs saved places (geofences) across the circle through the shared Realtime
//  Database, so a place added, edited, or removed on one phone shows up on the
//  other. Local persistence still works offline; this layer uploads this device's
//  places and reconciles them with the shared copy, re-arming geofence monitoring
//  for places that arrive from the circle.
//

import Foundation

final class PlacesSyncService {
    static let shared = PlacesSyncService()

    private let circleID = "main"
    private let pollInterval: TimeInterval = 5.0
    private var pollTimer: Timer?

    /// Place IDs we have actually seen in the shared copy. A local place is only
    /// removed when it disappears from this set's remote view, so places created
    /// offline (not yet uploaded) are never wiped by a poll.
    private var knownRemoteIDs: Set<UUID> = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private var engine: BackgroundTrackingEngine { .shared }

    private init() {}

    /// Configured Realtime Database base URL; empty until set in Info.plist, in
    /// which case sync no-ops and places remain local-only.
    private var databaseURL: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FirebaseDatabaseURL") as? String else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Lifecycle

    func start() {
        pollTimer?.invalidate()
        knownRemoteIDs = []

        // Load this device's locally-cached places and push them to the shared copy
        // so they reach the other phone and survive reconciliation.
        engine.restorePersistedGeofences()
        for zone in engine.activeGeofences { publish(zone) }

        // First reconcile fires after one interval, giving the uploads time to land.
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.fetchRemotePlaces()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        knownRemoteIDs = []
    }

    // MARK: - Push

    func publish(_ zone: GeofenceZone) {
        guard let base = databaseURL,
              let url = URL(string: "\(base)/circles/\(circleID)/places/\(zone.id.uuidString).json"),
              let body = try? JSONEncoder().encode(zone) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request).resume()
    }

    func remove(id: UUID) {
        guard let base = databaseURL,
              let url = URL(string: "\(base)/circles/\(circleID)/places/\(id.uuidString).json") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        session.dataTask(with: request).resume()
    }

    // MARK: - Poll

    private func fetchRemotePlaces() {
        guard let base = databaseURL,
              let url = URL(string: "\(base)/circles/\(circleID)/places.json") else { return }
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else { return }
            // An empty node decodes as "null" (not a dictionary), so decoding fails:
            // treat that as "no shared places yet" and skip, never wiping local data.
            guard let decoded = try? JSONDecoder().decode([String: GeofenceZone].self, from: data) else { return }

            let remoteZones = Array(decoded.values)
            let remoteIDs = Set(remoteZones.map { $0.id })
            let removedIDs = self.knownRemoteIDs.subtracting(remoteIDs)
            self.knownRemoteIDs = remoteIDs

            for zone in remoteZones {
                self.engine.upsertSyncedGeofence(zone)
            }
            for id in removedIDs {
                self.engine.removeSyncedGeofence(id: id)
            }
        }.resume()
    }
}
