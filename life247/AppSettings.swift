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
    static let autoRouteRecording = "life247.autoRouteRecording"
    static let useMiles = "life247.useMiles"
    static let mapStyle = "life247.mapStyle"
}

extension UserDefaults {
    /// Seeds the toggles that should start enabled so first launch matches the UI.
    static func registerLife247Defaults() {
        standard.register(defaults: [
            AppSettingsKeys.shareLocation: true,
            AppSettingsKeys.highAccuracy: true,
            AppSettingsKeys.placeAlerts: true,
            AppSettingsKeys.lowBatteryAlerts: true,
            AppSettingsKeys.autoRouteRecording: true,
            AppSettingsKeys.useMiles: false,
            AppSettingsKeys.mapStyle: MapStyleChoice.standard.rawValue
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
}
