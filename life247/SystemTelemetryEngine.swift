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
    /// Most recent speed in metres/second (0 when unknown or stationary).
    @Published var liveSpeed: Double = 0
    @Published var liveTrackingActive = false
    @Published var recordedDrivesHistory: [HistoricalRouteDrive] = []
    @Published var activeGeofences: [GeofenceZone] = []
    
    @Published var currentActiveZoneID: UUID? = nil
    @Published var insideZoneTimerText = "00:00:00"

    /// When the operator last settled at their current location. Persisted and
    /// only reset on real movement, so it survives app restarts.
    @Published var atLocationSince: Date = Date()
    private var locationAnchor: CLLocationCoordinate2D?
    private let locationAnchorResetMeters: Double = 150
    private let persistedAnchorLatKey = "life247.anchorLat"
    private let persistedAnchorLonKey = "life247.anchorLon"
    private let persistedAtLocationSinceKey = "life247.atLocationSince"
    
    private let locationManager = CLLocationManager()
    private var driveStartedDate: Date?
    private var pathSequence: [CLLocationCoordinate2D] = []
    private var incrementalDistanceMeters: Double = 0.0
    private var driveMaxSpeed: Double = 0.0
    private var tripStationarySince: Date?
    private let autoTripMovingThresholdKmh = 1.5
    private let autoTripStopStationarySeconds: TimeInterval = 120
    private let autoTripMinDistanceMeters: Double = 60
    private var perimeterTimer: Timer?
    private var zoneArrivalTimestamp: Date?
    private let persistedGeofencesKey = "life247.savedGeofences"
    private let persistedDrivesKey = "life247.recordedDrives"
    private let maxPersistedDrives = 100
    private var wantsAmbientUpdates = false
    
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0
        locationManager.pausesLocationUpdatesAutomatically = false
        
        UIDevice.current.isBatteryMonitoringEnabled = true
        restoreLocationAnchor()
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
        level < 0 ? 100 : Int((level * 100).rounded())
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
                self.driveMaxSpeed = 0.0
                self.liveTrackingActive = true
                self.startLocationUpdatesIfAuthorized()
            } else {
                // Keep the ambient location stream alive (live position + next
                // auto-trip detection); only fully stop when nothing wants updates.
                if !self.wantsAmbientUpdates {
                    self.locationManager.stopUpdatingLocation()
                }
                self.liveTrackingActive = false
                self.tripStationarySince = nil
                if let start = self.driveStartedDate,
                   self.pathSequence.count > 1,
                   self.incrementalDistanceMeters >= self.autoTripMinDistanceMeters {
                    let drive = HistoricalRouteDrive(startTime: start, endTime: Date(), totalDistanceMeters: self.incrementalDistanceMeters, maxSpeedMetersPerSecond: self.driveMaxSpeed, breadcrumbs: self.pathSequence)
                    self.recordedDrivesHistory.insert(drive, at: 0)
                    self.finalizeCompletedTrip(drive)
                }
                self.driveStartedDate = nil
            }
        }
    }
    
    func registerGeofenceHardwareBoundary(for zone: GeofenceZone) {
        DispatchQueue.main.async {
            self.activeGeofences.append(zone)
            self.startMonitoring(for: zone)
            self.persistGeofences()
            PlacesSyncService.shared.publish(zone)
        }
    }
    
    /// Applies an edited place: updates name/emoji/radius and re-arms monitoring
    /// when the radius changes so the region matches the new value.
    func updateGeofenceZone(_ zone: GeofenceZone) {
        DispatchQueue.main.async {
            guard let index = self.activeGeofences.firstIndex(where: { $0.id == zone.id }) else { return }
            let radiusChanged = self.activeGeofences[index].radius != zone.radius
            self.activeGeofences[index] = zone

            if radiusChanged {
                self.rearmMonitoring(for: zone)
            }
            self.persistGeofences()
            PlacesSyncService.shared.publish(zone)
        }
    }

    /// Reflects the user's accuracy preference onto the location manager.
    func applyAccuracyPreference(highAccuracy: Bool) {
        locationManager.desiredAccuracy = highAccuracy ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyHundredMeters
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
            PlacesSyncService.shared.remove(id: id)
        }
    }

    // MARK: - Circle-synced places

    /// Adds or updates a place that arrived from the shared circle copy, re-arming
    /// monitoring when its geometry changed. Does not re-publish (avoids sync loops).
    func upsertSyncedGeofence(_ zone: GeofenceZone) {
        DispatchQueue.main.async {
            if let index = self.activeGeofences.firstIndex(where: { $0.id == zone.id }) {
                guard self.activeGeofences[index] != zone else { return }
                let geometryChanged = self.activeGeofences[index].radius != zone.radius
                    || self.activeGeofences[index].latitude != zone.latitude
                    || self.activeGeofences[index].longitude != zone.longitude
                self.activeGeofences[index] = zone
                if geometryChanged { self.rearmMonitoring(for: zone) }
            } else {
                self.activeGeofences.append(zone)
                self.startMonitoring(for: zone)
            }
            self.persistGeofences()
        }
    }

    /// Removes a place that was deleted elsewhere in the circle. Does not re-publish.
    func removeSyncedGeofence(id: UUID) {
        DispatchQueue.main.async {
            guard self.activeGeofences.contains(where: { $0.id == id }) else { return }
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

    private func startMonitoring(for zone: GeofenceZone) {
        let region = CLCircularRegion(center: zone.coordinate, radius: zone.radius, identifier: zone.id.uuidString)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
    }

    private func rearmMonitoring(for zone: GeofenceZone) {
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == zone.id.uuidString }) {
            locationManager.stopMonitoring(for: region)
        }
        startMonitoring(for: zone)
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
            startMonitoring(for: zone)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            let speed = max(0, location.speed)
            self.liveLocation = location.coordinate
            self.liveSpeed = speed
            self.updateLocationDwell(for: location)
            if self.liveTrackingActive {
                self.driveMaxSpeed = max(self.driveMaxSpeed, speed)
                if let lastNode = self.pathSequence.last {
                    let delta = location.distance(from: CLLocation(latitude: lastNode.latitude, longitude: lastNode.longitude))
                    self.incrementalDistanceMeters += delta
                }
                self.pathSequence.append(location.coordinate)
            }
            self.evaluateAutomaticTripRecording(speedMetersPerSecond: speed)
        }
    }

    /// Starts a trip when the operator begins moving (walking or driving) and ends
    /// it after a sustained stationary period, so both walks and drives are logged
    /// automatically. Gated on the "Auto Trip Recording" preference.
    private func evaluateAutomaticTripRecording(speedMetersPerSecond speed: Double) {
        guard UserDefaults.standard.bool(forKey: AppSettingsKeys.autoRouteRecording) else { return }
        let kmh = speed * 3.6

        if !liveTrackingActive {
            // Only begin a trip once the operator is moving AND outside every saved
            // place, so time spent at home/work doesn't get logged as a trip.
            if kmh >= autoTripMovingThresholdKmh, !isInsideAnyPlace() {
                synchronizeTrackingState(isActive: true)
            }
            return
        }

        if kmh >= autoTripMovingThresholdKmh {
            tripStationarySince = nil
        } else if let since = tripStationarySince {
            if Date().timeIntervalSince(since) >= autoTripStopStationarySeconds {
                synchronizeTrackingState(isActive: false)
            }
        } else {
            tripStationarySince = Date()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if let uuid = UUID(uuidString: region.identifier), let zone = activeGeofences.first(where: { $0.id == uuid }) {
            // Only the *other* phone is alerted about my arrival (via relay + their
            // in-app roster detection); this device doesn't notify itself.
            RelayPushService.shared.relayPlaceArrival(zone.name)
            setupZoneMetrologyTracking(for: uuid)
            // Arriving at a place ends the current trip — trips only cover travel
            // between places, not time spent inside one.
            if liveTrackingActive {
                synchronizeTrackingState(isActive: false)
            }
        }
    }

    // MARK: - Time at location

    /// Restores the persisted location anchor and dwell start so the "time at
    /// location" counter keeps running across app restarts.
    private func restoreLocationAnchor() {
        let defaults = UserDefaults.standard
        if let since = defaults.object(forKey: persistedAtLocationSinceKey) as? Double {
            atLocationSince = Date(timeIntervalSince1970: since)
        }
        if defaults.object(forKey: persistedAnchorLatKey) != nil {
            locationAnchor = CLLocationCoordinate2D(
                latitude: defaults.double(forKey: persistedAnchorLatKey),
                longitude: defaults.double(forKey: persistedAnchorLonKey)
            )
        }
    }

    /// Keeps the dwell timer running while the operator stays put and restarts it
    /// only once they move beyond `locationAnchorResetMeters` from the anchor.
    private func updateLocationDwell(for location: CLLocation) {
        if let anchor = locationAnchor {
            let moved = location.distance(from: CLLocation(latitude: anchor.latitude, longitude: anchor.longitude))
            if moved <= locationAnchorResetMeters { return }
        }
        locationAnchor = location.coordinate
        atLocationSince = Date()
        persistLocationAnchor()
    }

    private func persistLocationAnchor() {
        let defaults = UserDefaults.standard
        if let anchor = locationAnchor {
            defaults.set(anchor.latitude, forKey: persistedAnchorLatKey)
            defaults.set(anchor.longitude, forKey: persistedAnchorLonKey)
        }
        defaults.set(atLocationSince.timeIntervalSince1970, forKey: persistedAtLocationSinceKey)
    }

    /// Whether the operator's live position currently falls inside any saved place.
    private func isInsideAnyPlace() -> Bool {
        guard let here = liveLocation else { return false }
        let location = CLLocation(latitude: here.latitude, longitude: here.longitude)
        return activeGeofences.contains { zone in
            location.distance(from: CLLocation(latitude: zone.latitude, longitude: zone.longitude)) <= zone.radius
        }
    }

    /// Persists, publishes to the circle, and announces a freshly completed trip.
    private func finalizeCompletedTrip(_ drive: HistoricalRouteDrive) {
        persistDrives()
        TripsSyncService.shared.publish(drive)
        let summary = "\(drive.modeLabel) · \(UnitFormatter.durationString(seconds: drive.duration)) · top speed \(UnitFormatter.speedString(metersPerSecond: drive.maxSpeedMetersPerSecond))"
        NotificationManager.shared.post(title: "Trip complete", body: summary, category: .trip)
        RelayPushService.shared.relayTripComplete(duration: drive.duration, topSpeedMetersPerSecond: drive.maxSpeedMetersPerSecond)
    }

    // MARK: - Trip persistence

    private func persistDrives() {
        let capped = Array(recordedDrivesHistory.prefix(maxPersistedDrives))
        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: persistedDrivesKey)
        }
    }

    /// Reloads this device's previously recorded trips. Safe to call repeatedly;
    /// it only seeds when the in-memory history is still empty.
    func restorePersistedDrives() {
        guard recordedDrivesHistory.isEmpty,
              let data = UserDefaults.standard.data(forKey: persistedDrivesKey),
              let drives = try? JSONDecoder().decode([HistoricalRouteDrive].self, from: data) else { return }
        recordedDrivesHistory = drives
    }

    /// Clears this device's trip history locally and removes it from the circle.
    func clearTripHistory() {
        recordedDrivesHistory.removeAll()
        persistDrives()
        TripsSyncService.shared.clearOwnTrips()
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if let uuid = UUID(uuidString: region.identifier), let zone = activeGeofences.first(where: { $0.id == uuid }) {
            // Departure is announced only to the other phone, not to this device.
            RelayPushService.shared.relayPlaceDeparture(zone.name)
            teardownZoneMetrologyTracking()
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

    /// Province / territory codes used to recognise Canadian completions even
    /// when MapKit omits the country name for nearby (domestic) results.
    private let canadianProvinceCodes: Set<String> = [
        "AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT"
    ]
    
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
            self.lookupResults = completer.results.filter { self.isCanadian($0) }
            self.networkOperationActive = false
        }
    }

    /// Keeps only completions that resolve to a Canadian address. MapKit's
    /// `region` only *biases* results toward Canada, so US (and other) addresses
    /// still appear; this filters them out.
    private func isCanadian(_ completion: MKLocalSearchCompletion) -> Bool {
        let text = "\(completion.title) \(completion.subtitle)"
        let lower = text.lowercased()
        if lower.contains("united states") || lower.contains("usa") { return false }
        if lower.contains("canada") { return true }
        // Domestic completions sometimes omit the country; fall back to matching a
        // province/territory code token (e.g. "Toronto, ON").
        let tokens = text
            .components(separatedBy: CharacterSet(charactersIn: ", "))
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        return tokens.contains { canadianProvinceCodes.contains($0) }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lookupResults = []
            self.networkOperationActive = false
        }
    }
}
