//
//  AppSettings.swift
//  life247
//
//  Centralized user-preference keys, defaults, and formatting helpers.
//

import SwiftUI
import MapKit

enum AppSettingsKeys {
    static let shareLocation = "life247.shareLocation"
    static let highAccuracy = "life247.highAccuracy"
    static let placeAlerts = "life247.placeAlerts"
    static let lowBatteryAlerts = "life247.lowBatteryAlerts"
    static let chatAlerts = "life247.chatAlerts"
    static let autoRouteRecording = "life247.autoRouteRecording"
    static let useMiles = "life247.useMiles"
    static let mapStyle = "life247.mapStyle"
    static let relayPushEnabled = "life247.relayPushEnabled"
    static let relayTopic = "life247.relayTopic"
}

extension UserDefaults {
    /// Seeds the toggles that should start enabled so first launch matches the UI.
    static func registerLife247Defaults() {
        standard.register(defaults: [
            AppSettingsKeys.shareLocation: true,
            AppSettingsKeys.highAccuracy: true,
            AppSettingsKeys.placeAlerts: true,
            AppSettingsKeys.lowBatteryAlerts: true,
            AppSettingsKeys.chatAlerts: true,
            AppSettingsKeys.autoRouteRecording: true,
            AppSettingsKeys.useMiles: false,
            AppSettingsKeys.mapStyle: MapStyleChoice.standard.rawValue,
            AppSettingsKeys.relayPushEnabled: false,
            AppSettingsKeys.relayTopic: ""
        ])
    }
}

enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .satellite: return "Satellite"
        case .hybrid: return "Hybrid"
        }
    }

    var symbol: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe.americas.fill"
        case .hybrid: return "map.fill"
        }
    }

    var style: MapStyle {
        switch self {
        case .standard: return .standard
        case .satellite: return .imagery
        case .hybrid: return .hybrid
        }
    }
}

/// Speed/distance formatting that honors the user's unit preference.
enum UnitFormatter {
    static var useMiles: Bool { UserDefaults.standard.bool(forKey: AppSettingsKeys.useMiles) }

    /// Formats a raw speed (meters/second) using the active unit preference.
    static func speedString(metersPerSecond: Double) -> String {
        let speed = max(0, metersPerSecond)
        if useMiles {
            return "\(Int(speed * 2.23694)) mph"
        }
        return "\(Int(speed * 3.6)) km/h"
    }

    /// Formats a distance (meters) using the active unit preference.
    static func distanceString(meters: Double) -> String {
        let value = max(0, meters)
        if useMiles {
            return String(format: "%.1f mi", value / 1609.34)
        }
        return String(format: "%.1f km", value / 1000.0)
    }

    /// Compact "1h 12m" / "12m 30s" style duration formatting.
    static func durationString(seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }
}
