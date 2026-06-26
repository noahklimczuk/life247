//
//  AppModels.swift
//  life247
//

import Foundation
import CoreLocation

enum TrackedUserActivity: String, Codable {
    case stationary = "Stationary"
    case walking = "Walking"
    case driving = "Driving"
}

struct UserState: Identifiable, Codable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var batteryPercentage: Int
    var currentSpeed: Double
    var activity: TrackedUserActivity
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct GeofenceZone: Identifiable, Codable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let emojiIcon: String
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct TelemetryStop: Identifiable, Codable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let arrivalTime: Date
    let departureTime: Date
    let duration: TimeInterval
    
    enum CodingKeys: String, CodingKey {
        case id
        case latitude
        case longitude
        case arrivalTime
        case departureTime
        case duration
    }
    
    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, arrivalTime: Date, departureTime: Date, duration: TimeInterval) {
        self.id = id
        self.coordinate = coordinate
        self.arrivalTime = arrivalTime
        self.departureTime = departureTime
        self.duration = duration
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        self.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        self.arrivalTime = try container.decode(Date.self, forKey: .arrivalTime)
        self.departureTime = try container.decode(Date.self, forKey: .departureTime)
        self.duration = try container.decode(TimeInterval.self, forKey: .duration)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(arrivalTime, forKey: .arrivalTime)
        try container.encode(departureTime, forKey: .departureTime)
        try container.encode(duration, forKey: .duration)
    }
}

struct HistoricalRouteDrive: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let totalDistanceMeters: Double
    let breadcrumbs: [CLLocationCoordinate2D]
    
    enum CodingKeys: String, CodingKey {
        case id
        case startTime
        case endTime
        case totalDistanceMeters
        case breadcrumbsLatitudes
        case breadcrumbsLongitudes
    }
    
    init(id: UUID = UUID(), startTime: Date, endTime: Date, totalDistanceMeters: Double, breadcrumbs: [CLLocationCoordinate2D]) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.totalDistanceMeters = totalDistanceMeters
        self.breadcrumbs = breadcrumbs
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.startTime = try container.decode(Date.self, forKey: .startTime)
        self.endTime = try container.decode(Date.self, forKey: .endTime)
        self.totalDistanceMeters = try container.decode(Double.self, forKey: .totalDistanceMeters)
        
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
        
        let lats = breadcrumbs.map { $0.latitude }
        let lons = breadcrumbs.map { $0.longitude }
        try container.encode(lats, forKey: .breadcrumbsLatitudes)
        try container.encode(lons, forKey: .breadcrumbsLongitudes)
    }
}

struct MapPinNode: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let isCurrentUser: Bool
}

struct CanadaPostFindResponse: Decodable, Sendable {
    let items: [CanadaPostSuggestion]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

struct CanadaPostSuggestion: Identifiable, Decodable, Sendable {
    var id: String { idValue }
    let idValue: String
    let text: String
    let description: String
    let nextStep: String
    
    enum CodingKeys: String, CodingKey {
        case idValue = "Id"
        case text = "Text"
        case description = "Description"
        case nextStep = "Next"
    }
}

struct CanadaPostRetrieveResponse: Decodable, Sendable {
    let items: [CanadaPostAddressDetail]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

struct CanadaPostAddressDetail: Decodable, Sendable {
    let line1: String
    let city: String
    let provinceCode: String
    let postalCode: String
    
    enum CodingKeys: String, CodingKey {
        case line1 = "Line1"
        case city = "City"
        case provinceCode = "Province"
        case postalCode = "PostalCode"
    }
}
