//
//  SessionAuthContext.swift
//  life247
//

import Foundation
import SwiftUI
import Combine
import CoreLocation
import UIKit

class SessionAuthContext: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUserProfile: UserState? = nil
    @Published var loginErrorMessage: String? = nil
    
    private let keychainIdentifier = "com.life247.app.session"
    
    init() {
        checkExistingSecureSession()
    }
    
    /// Verifies if there's an active valid session stored in secure storage on startup
    func checkExistingSecureSession() {
        if let savedSessionData = KeychainHelper.shared.read(service: keychainIdentifier, account: "user_token") {
            if let sessionString = String(data: savedSessionData, encoding: .utf8), !sessionString.isEmpty {
                
                // Track dynamic battery metrics directly from the device hardware state
                UIDevice.current.isBatteryMonitoringEnabled = true
                let positiveBattery = BackgroundTrackingEngine.batteryPercentage(from: UIDevice.current.batteryLevel)

                // Fetch last known location from engine fallback if available instead of hardcoding 0.0
                let lastLat = BackgroundTrackingEngine.shared.liveLocation?.latitude ?? 43.6532 // Default Toronto fallback
                let lastLon = BackgroundTrackingEngine.shared.liveLocation?.longitude ?? -79.3832

                // ALWAYS publish UI state updates safely to the Main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.currentUserProfile = UserState(
                        id: "NODE-\(Int.random(in: 100...999))",
                        name: UIDevice.current.name,
                        latitude: lastLat,
                        longitude: lastLon,
                        batteryPercentage: positiveBattery,
                        currentSpeed: 0.0,
                        activity: .stationary
                    )
                    self.isAuthenticated = true

                    // Keep live battery telemetry running for restored sessions too
                    BackgroundTrackingEngine.shared.startLiveBatteryMonitoring(authContext: self)
                }
            }
        }
    }
    
    /// Authenticates credentials dynamically matching device contexts
    func attemptSecureLogin(username: String, password: String) {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Updated to allow "noah" or "dash" with the required password
        if (cleanUsername == "noah" || cleanUsername == "dash") && password == "Dec102025" {
            let mockToken = UUID().uuidString
            if let tokenData = mockToken.data(using: .utf8) {
                KeychainHelper.shared.save(tokenData, service: keychainIdentifier, account: "user_token")
            }
            
            UIDevice.current.isBatteryMonitoringEnabled = true
            let positiveBattery = BackgroundTrackingEngine.batteryPercentage(from: UIDevice.current.batteryLevel)

            let lastLat = BackgroundTrackingEngine.shared.liveLocation?.latitude ?? 43.6532
            let lastLon = BackgroundTrackingEngine.shared.liveLocation?.longitude ?? -79.3832
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.loginErrorMessage = nil
                self.currentUserProfile = UserState(
                    id: "NODE-\(Int.random(in: 100...999))",
                    name: UIDevice.current.name,
                    latitude: lastLat,
                    longitude: lastLon,
                    batteryPercentage: positiveBattery,
                    currentSpeed: 0.0,
                    activity: .stationary
                )
                self.isAuthenticated = true
                
                // Boot live telemetry battery tracking directly upon login success
                BackgroundTrackingEngine.shared.startLiveBatteryMonitoring(authContext: self)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.loginErrorMessage = "Invalid credentials."
            }
        }
    }
    
    /// Clears active credentials data safely without depending on static engine instances
    func performSecureLogout() {
        KeychainHelper.shared.delete(service: keychainIdentifier, account: "user_token")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isAuthenticated = false
            self.currentUserProfile = nil
            self.loginErrorMessage = nil
        }
    }
}
