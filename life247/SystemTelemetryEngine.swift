//
//  SystemTelemetryEngine.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-15.
//

import Foundation
import SwiftUI
import Combine
import UserNotifications
import MapKit
import CoreLocation
import UIKit

class BackgroundTrackingEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = BackgroundTrackingEngine()
    
    @Published var liveLocation: CLLocationCoordinate2D?
    @Published var liveTrackingActive = false
    @Published var recordedDrivesHistory: [HistoricalRouteDrive] = []
    @Published var activeGeofences: [GeofenceZone] = []
    
    @Published var currentActiveZoneID: UUID? = nil
    @Published var insideZoneTimerText = "00:00:00"
    
    private let locationManager = CLLocationManager()
    private var driveStartedDate: Date?
    private var pathSequence: [CLLocationCoordinate2D] = []
    private var incrementalDistanceMeters: Double = 0.0
    private var perimeterTimer: Timer?
    private var zoneArrivalTimestamp: Date?
    private let persistedGeofencesKey = "life247.savedGeofences"
    private var wantsAmbientUpdates = false
    
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0
        locationManager.pausesLocationUpdatesAutomatically = false
        
        UIDevice.current.isBatteryMonitoringEnabled = true
    }
    
    func startLiveBatteryMonitoring(authContext: SessionAuthContext) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        let initialLevel = UIDevice.current.batteryLevel
        if var profile = authContext.currentUserProfile {
            profile.batteryPercentage = Self.batteryPercentage(from: initialLevel)
            authContext.currentUserProfile = profile
        }
        
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let currentLevel = UIDevice.current.batteryLevel
            let batteryPct = Self.batteryPercentage(from: currentLevel)
            
            if var updatedProfile = authContext.currentUserProfile {
                updatedProfile.batteryPercentage = batteryPct
                authContext.currentUserProfile = updatedProfile
            }
        }
    }
    
    /// Converts a raw `UIDevice` battery level (-1 when unknown, e.g. Simulator) into a 0-100 percentage.
    static func batteryPercentage(from level: Float) -> Int {
        level < 0 ? 100 : Int(level * 100)
    }

    func initializeSystemHardwareAccess() {
        locationManager.requestAlwaysAuthorization()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Keeps `liveLocation` populated with the operator's current position so the
    /// rest of the UI (current address, map marker) reflects where they are now.
    /// Defers the actual start until location authorization is granted, so it is
    /// safe to call at launch before the permission prompt is answered.
    func beginAmbientLocationUpdates() {
        wantsAmbientUpdates = true
        startLocationUpdatesIfAuthorized()
    }

    /// Enables background updates (only when granted Always) and starts the
    /// location stream once the app is authorized. No-op until then.
    private func startLocationUpdatesIfAuthorized() {
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            locationManager.requestAlwaysAuthorization()
            return
        }
        if status == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
        }
        if wantsAmbientUpdates || liveTrackingActive {
            locationManager.startUpdatingLocation()
        }
    }

    /// Re-applies pending location requests once the user answers the prompt.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startLocationUpdatesIfAuthorized()
    }
    
    func synchronizeTrackingState(isActive varNewState: Bool) {
        DispatchQueue.main.async {
            if varNewState {
                self.driveStartedDate = Date()
                self.pathSequence = []
                self.incrementalDistanceMeters = 0.0
                self.liveTrackingActive = true
                self.startLocationUpdatesIfAuthorized()
            } else {
                self.locationManager.stopUpdatingLocation()
                self.liveTrackingActive = false
                if let start = self.driveStartedDate, self.pathSequence.count > 1 {
                    let drive = HistoricalRouteDrive(startTime: start, endTime: Date(), totalDistanceMeters: self.incrementalDistanceMeters, breadcrumbs: self.pathSequence)
                    self.recordedDrivesHistory.insert(drive, at: 0)
                }
                self.driveStartedDate = nil
            }
        }
    }
    
    func registerGeofenceHardwareBoundary(for zone: GeofenceZone) {
        DispatchQueue.main.async {
            self.activeGeofences.append(zone)
            let region = CLCircularRegion(center: zone.coordinate, radius: zone.radius, identifier: zone.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            self.locationManager.startMonitoring(for: region)
            self.persistGeofences()
        }
    }
    
    func clearGeofenceZone(id: UUID) {
        DispatchQueue.main.async {
            self.activeGeofences.removeAll(where: { $0.id == id })
            if let targetRegion = self.locationManager.monitoredRegions.first(where: { $0.identifier == id.uuidString }) {
                self.locationManager.stopMonitoring(for: targetRegion)
            }
            if self.currentActiveZoneID == id {
                self.teardownZoneMetrologyTracking()
            }
            self.persistGeofences()
        }
    }

    /// Persists the current saved places to disk so they survive app shutdown.
    private func persistGeofences() {
        if let data = try? JSONEncoder().encode(activeGeofences) {
            UserDefaults.standard.set(data, forKey: persistedGeofencesKey)
        }
    }

    /// Reloads previously saved places and re-arms their geofence monitoring.
    /// Safe to call repeatedly; already-active zones are skipped.
    func restorePersistedGeofences() {
        guard let data = UserDefaults.standard.data(forKey: persistedGeofencesKey),
              let zones = try? JSONDecoder().decode([GeofenceZone].self, from: data) else { return }

        for zone in zones where !activeGeofences.contains(where: { $0.id == zone.id }) {
            activeGeofences.append(zone)
            let region = CLCircularRegion(center: zone.coordinate, radius: zone.radius, identifier: zone.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            locationManager.startMonitoring(for: region)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.liveLocation = location.coordinate
            if self.liveTrackingActive {
                if let lastNode = self.pathSequence.last {
                    let delta = location.distance(from: CLLocation(latitude: lastNode.latitude, longitude: lastNode.longitude))
                    self.incrementalDistanceMeters += delta
                }
                self.pathSequence.append(location.coordinate)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if let uuid = UUID(uuidString: region.identifier), let zone = activeGeofences.first(where: { $0.id == uuid }) {
            dispatchLocalNotification(title: "Arrived at destination", message: "Entered your place: \(zone.name)")
            setupZoneMetrologyTracking(for: uuid)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if let uuid = UUID(uuidString: region.identifier), let zone = activeGeofences.first(where: { $0.id == uuid }) {
            dispatchLocalNotification(title: "Left region boundary", message: "Departed your place: \(zone.name)")
            teardownZoneMetrologyTracking()
            synchronizeTrackingState(isActive: true)
        }
    }
    
    private func setupZoneMetrologyTracking(for zoneID: UUID) {
        DispatchQueue.main.async {
            self.currentActiveZoneID = zoneID
            self.zoneArrivalTimestamp = Date()
            self.perimeterTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, let arrival = self.zoneArrivalTimestamp else { return }
                let elapsed = Date().timeIntervalSince(arrival)
                let hours = Int(elapsed) / 3600
                let mins = (Int(elapsed) % 3600) / 60
                let secs = Int(elapsed) % 60
                self.insideZoneTimerText = String(format: "%02d:%02d:%02d", hours, mins, secs)
            }
        }
    }
    
    private func teardownZoneMetrologyTracking() {
        DispatchQueue.main.async {
            self.perimeterTimer?.invalidate()
            self.perimeterTimer = nil
            self.currentActiveZoneID = nil
            self.zoneArrivalTimestamp = nil
            self.insideZoneTimerText = "00:00:00"
        }
    }
    
    private func dispatchLocalNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

// MARK: - Free Native Apple Address Autocomplete Lookup Service
class AppleAddressLookupService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var lookupResults: [MKLocalSearchCompletion] = []
    @Published var networkOperationActive = false
    var isProgrammaticUpdate = false
    
    private var searchCompleter = MKLocalSearchCompleter()
    private var cancellable: AnyCancellable?
    private let searchSubject = PassthroughSubject<String, Never>()
    
    override init() {
        super.init()
        searchCompleter.delegate = self
        searchCompleter.resultTypes = .address
        
        // Setup bounding region over Canada map center coordinates
        searchCompleter.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468),
            span: MKCoordinateSpan(latitudeDelta: 25.0, longitudeDelta: 25.0)
        )
        
        // Debounce pipeline to prevent interface freezing and server rate limits
        cancellable = searchSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.isEmpty {
                    self.lookupResults = []
                    self.networkOperationActive = false
                } else {
                    self.searchCompleter.queryFragment = query
                }
            }
    }
    
    func executeRemoteSearchCall(text: String) {
        networkOperationActive = true
        searchSubject.send(text)
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.lookupResults = completer.results
            self.networkOperationActive = false
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lookupResults = []
            self.networkOperationActive = false
        }
    }
}
