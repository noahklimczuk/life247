//
//  AppModels.swift
//  life247
//

import Foundation
import CoreLocation

// MARK: - Activity

enum TrackedUserActivity: String, Codable {
    case stationary = "Stationary"
    case walking = "Walking"
    case driving = "Driving"
}

// MARK: - User State

struct UserState: Identifiable, Codable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var batteryPercentage: Int
    var currentSpeed: Double
    var activity: TrackedUserActivity
    var isCharging: Bool = false
    var isSOS: Bool = false
    var atLocationSince: Date = Date()

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    let senderId: String
    let senderName: String
    let text: String
    let timestamp: Date

    var sentAt: Date { timestamp }
}

// MARK: - Geofence Zone

struct GeofenceZone: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let latitude: Double
    let longitude: Double
    var radius: Double
    var emojiIcon: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Recorded Drive History

struct HistoricalRouteDrive: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let totalDistanceMeters: Double
    let maxSpeedMetersPerSecond: Double
    let breadcrumbs: [CLLocationCoordinate2D]

    /// Trip duration in seconds.
    var duration: TimeInterval { max(0, endTime.timeIntervalSince(startTime)) }

    /// Average speed across the whole trip (meters/second).
    var averageSpeedMetersPerSecond: Double {
        duration > 0 ? totalDistanceMeters / duration : 0
    }

    /// Whether the trip reads as a drive vs a walk, inferred from its pace.
    /// Average pace over ~10 km/h is treated as driving.
    var isDriving: Bool { averageSpeedMetersPerSecond * 3.6 > 10 }

    var modeLabel: String { isDriving ? "Drive" : "Walk" }
    var modeSymbol: String { isDriving ? "car.fill" : "figure.walk" }

    enum CodingKeys: String, CodingKey {
        case id
        case startTime
        case endTime
        case totalDistanceMeters
        case maxSpeedMetersPerSecond
        case breadcrumbsLatitudes
        case breadcrumbsLongitudes
    }

    init(id: UUID = UUID(), startTime: Date, endTime: Date, totalDistanceMeters: Double, maxSpeedMetersPerSecond: Double = 0, breadcrumbs: [CLLocationCoordinate2D]) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.totalDistanceMeters = totalDistanceMeters
        self.maxSpeedMetersPerSecond = maxSpeedMetersPerSecond
        self.breadcrumbs = breadcrumbs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.startTime = try container.decode(Date.self, forKey: .startTime)
        self.endTime = try container.decode(Date.self, forKey: .endTime)
        self.totalDistanceMeters = try container.decode(Double.self, forKey: .totalDistanceMeters)
        self.maxSpeedMetersPerSecond = try container.decodeIfPresent(Double.self, forKey: .maxSpeedMetersPerSecond) ?? 0

        let lats = try container.decode([Double].self, forKey: .breadcrumbsLatitudes)
        let lons = try container.decode([Double].self, forKey: .breadcrumbsLongitudes)

        var points: [CLLocationCoordinate2D] = []
        for i in 0..<min(lats.count, lons.count) {
            points.append(CLLocationCoordinate2D(latitude: lats[i], longitude: lons[i]))
        }
        self.breadcrumbs = points
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(totalDistanceMeters, forKey: .totalDistanceMeters)
        try container.encode(maxSpeedMetersPerSecond, forKey: .maxSpeedMetersPerSecond)

        let lats = breadcrumbs.map { $0.latitude }
        let lons = breadcrumbs.map { $0.longitude }
        try container.encode(lats, forKey: .breadcrumbsLatitudes)
        try container.encode(lons, forKey: .breadcrumbsLongitudes)
    }
}
