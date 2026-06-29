//
//  TripsSyncService.swift
//  life247
//
//  Syncs recorded trips across the circle through the shared Realtime Database so
//  each person can browse the other's trips, grouped by user. This device only
//  ever writes its own trips (under its username) and publishes the rest of the
//  circle's trips for the UI. Trips are immutable once recorded, so syncing is a
//  simple publish-on-completion plus a periodic poll of everyone else's history.
//

import Foundation

final class TripsSyncService: ObservableObject {
    static let shared = TripsSyncService()

    /// Trips recorded by every *other* circle member, keyed by their username and
    /// sorted newest-first. This device's own trips live in the tracking engine.
    @Published var remoteTripsByUser: [String: [HistoricalRouteDrive]] = [:]

    private let circleID = "main"
    private let pollInterval: TimeInterval = 8.0
    private var pollTimer: Timer?
    private var myUsername = ""

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private var engine: BackgroundTrackingEngine { .shared }

    private init() {}

    /// Configured Realtime Database base URL; empty until set in Info.plist, in
    /// which case sync no-ops and trips remain local-only.
    private var databaseURL: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FirebaseDatabaseURL") as? String else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Lifecycle

    func start(username: String) {
        myUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        pollTimer?.invalidate()
        remoteTripsByUser = [:]

        // Restore this device's locally-cached trips and (re)publish them so the
        // partner sees the full history, then begin polling for everyone else's.
        engine.restorePersistedDrives()
        for drive in engine.recordedDrivesHistory { publish(drive) }

        fetchRemoteTrips()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.fetchRemoteTrips()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        myUsername = ""
        remoteTripsByUser = [:]
    }

    // MARK: - Push

    func publish(_ drive: HistoricalRouteDrive) {
        guard !myUsername.isEmpty,
              let base = databaseURL,
              let url = URL(string: "\(base)/circles/\(circleID)/trips/\(myUsername)/\(drive.id.uuidString).json"),
              let body = try? JSONEncoder().encode(drive) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request).resume()
    }

    /// Removes all of this device's trips from the shared copy (used by "Clear
    /// Trip History"), leaving other members' trips untouched.
    func clearOwnTrips() {
        guard !myUsername.isEmpty,
              let base = databaseURL,
              let url = URL(string: "\(base)/circles/\(circleID)/trips/\(myUsername).json") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        session.dataTask(with: request).resume()
    }

    // MARK: - Poll

    private func fetchRemoteTrips() {
        guard let base = databaseURL,
              let url = URL(string: "\(base)/circles/\(circleID)/trips.json") else { return }
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else { return }
            // An empty node decodes as "null", so decoding fails: treat as "no
            // shared trips yet" and leave the current view untouched.
            guard let decoded = try? JSONDecoder().decode([String: [String: HistoricalRouteDrive]].self, from: data) else { return }

            var grouped: [String: [HistoricalRouteDrive]] = [:]
            for (username, trips) in decoded where username != self.myUsername {
                let sorted = trips.values.sorted { $0.startTime > $1.startTime }
                if !sorted.isEmpty { grouped[username] = sorted }
            }

            DispatchQueue.main.async {
                self.remoteTripsByUser = grouped
            }
        }.resume()
    }
}
