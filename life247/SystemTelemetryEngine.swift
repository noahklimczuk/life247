//
//  SystemTelemetryEngine.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-15.
//

//
//  SystemTelemetryEngine.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-15.
//

import Foundation
import SwiftUI
import CoreLocation
import Combine
import UserNotifications
import MapKit

class SessionAuthContext: ObservableObject {
    @AppStorage("app.session.isLoggedIn") var isAuthenticated: Bool = false
    @Published var currentUserProfile: UserState?
    @Published var loginErrorMessage: String? = nil
    
    private let kService = "com.life247.auth"
    private let kAccount = "currentSessionUser"
    
    private let validCredentials = [
        "noah": "Dec102025",
        "dash": "Dec102025"
    ]
    
    init() {
        hydrateSessionData()
    }
    
    func hydrateSessionData() {
        if isAuthenticated, let data = KeychainHelper.shared.read(service: kService, account: kAccount) {
            currentUserProfile = try? JSONDecoder().decode(UserState.self, from: data)
        } else {
            isAuthenticated = false
        }
    }
    
    func attemptSecureLogin(username: String, password: String) {
        let normalizedUser = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let correctPassword = validCredentials[normalizedUser] else {
            self.loginErrorMessage = "Access Denied: Invalid Username"
            return
        }
        
        guard password == correctPassword else {
            self.loginErrorMessage = "Access Denied: Incorrect Password"
            return
        }
        
        UIDevice.current.isBatteryMonitoringEnabled = true
        let devicePct = Int(abs(UIDevice.current.batteryLevel) * 100)
        let batteryVal = devicePct == 0 ? 84 : devicePct
        
        let profile = UserState(
            id: UUID().uuidString,
            name: normalizedUser.capitalized,
            latitude: 43.6532,
            longitude: -79.3832,
            batteryPercentage: batteryVal,
            currentSpeed: 0.0,
            activity: .stationary
        )
        
        if let encoded = try? JSONEncoder().encode(profile) {
            KeychainHelper.shared.save(encoded, service: kService, account: kAccount)
            self.currentUserProfile = profile
            self.loginErrorMessage = nil
            withAnimation {
                self.isAuthenticated = true
            }
        }
    }
    
    func performSecureLogout() {
        KeychainHelper.shared.delete(service: kService, account: kAccount)
        self.currentUserProfile = nil
        withAnimation {
            self.isAuthenticated = false
        }
    }
}

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
    
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        UIDevice.current.isBatteryMonitoringEnabled = true
    }
    
    func startLiveBatteryMonitoring(authContext: SessionAuthContext) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // Force an immediate update right now upon loading
        let initialLevel = UIDevice.current.batteryLevel
        if var profile = authContext.currentUserProfile {
            profile.batteryPercentage = initialLevel < 0 ? 84 : Int(initialLevel * 100)
            authContext.currentUserProfile = profile
        }
        
        // Register global listener for real-time device battery drops
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let currentLevel = UIDevice.current.batteryLevel
            let batteryPct = currentLevel < 0 ? 84 : Int(currentLevel * 100)
            
            if var updatedProfile = authContext.currentUserProfile {
                updatedProfile.batteryPercentage = batteryPct
                authContext.currentUserProfile = updatedProfile
            }
        }
    }
    
    func initializeSystemHardwareAccess() {
        locationManager.requestAlwaysAuthorization()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func synchronizeTrackingState(isActive varNewState: Bool) {
        DispatchQueue.main.async {
            if varNewState {
                self.driveStartedDate = Date()
                self.pathSequence = []
                self.incrementalDistanceMeters = 0.0
                self.liveTrackingActive = true
                self.locationManager.startUpdatingLocation()
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

class CanadaPostIntegrationService: ObservableObject {
    @Published var lookupResults: [CanadaPostSuggestion] = []
    @Published var networkOperationActive = false
    
    // BOUND: Active production API Key assigned from your platform console configuration
    private let tokenKey = "BA23-DF97-PH91-NX26"
    
    func executeRemoteSearchCall(text: String, lastId: String? = nil) {
        var components = URLComponents(string: "https://ws1.postescanada-canadapost.ca/AddressComplete/Interactive/Find/v2.10/json3ex.ws")
        var queries = [
            URLQueryItem(name: "Key", value: tokenKey),
            URLQueryItem(name: "SearchTerm", value: text),
            URLQueryItem(name: "Country", value: "CAN"),
            URLQueryItem(name: "LanguagePreference", value: "en")
        ]
        if let lastId = lastId { queries.append(URLQueryItem(name: "LastId", value: lastId)) }
        
        components?.queryItems = queries
        guard let url = components?.url else { return }
        
        DispatchQueue.main.async { self.networkOperationActive = true }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { self?.networkOperationActive = false }
                return
            }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let parsed = try? JSONDecoder().decode(CanadaPostFindResponse.self, from: data) {
                    self.networkOperationActive = false
                    self.lookupResults = parsed.items
                } else {
                    self.networkOperationActive = false
                }
            }
        }.resume()
    }
    
    func processSelection(for selection: CanadaPostSuggestion, currentSearchText: Binding<String>, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        if selection.nextStep.uppercased() == "RETRIEVE" {
            self.executeRemoteRetrieveCall(id: selection.idValue, completion: completion)
        } else {
            currentSearchText.wrappedValue = selection.text
            self.executeRemoteSearchCall(text: selection.text, lastId: selection.idValue)
            completion(nil)
        }
    }
    
    private func executeRemoteRetrieveCall(id: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        var components = URLComponents(string: "https://ws1.postescanada-canadapost.ca/AddressComplete/Interactive/Retrieve/v2.11/json3ex.ws")
        components?.queryItems = [
            URLQueryItem(name: "Key", value: self.tokenKey),
            URLQueryItem(name: "Id", value: id)
        ]
        
        guard let url = components?.url else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }
            
            Task { @MainActor in
                if let parsed = try? JSONDecoder().decode(CanadaPostRetrieveResponse.self, from: data),
                   let address = parsed.items.first {
                    
                    let formattedString = "\(address.line1), \(address.city), \(address.provinceCode), \(address.postalCode), Canada"
                    
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = formattedString
                    let search = MKLocalSearch(request: request)
                    
                    if let response = try? await search.start(),
                       let firstMapItem = response.mapItems.first {
                        completion(firstMapItem.location.coordinate)
                    } else {
                        completion(nil)
                    }
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }
}
