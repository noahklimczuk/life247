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
                let dynamicBattery = Int(UIDevice.current.batteryLevel * 100)
                let positiveBattery = dynamicBattery >= 0 ? dynamicBattery : 100
                
                self.currentUserProfile = UserState(
                    id: "NODE-\(Int.random(in: 100...999))",
                    name: UIDevice.current.name,
                    latitude: 0.0,
                    longitude: 0.0,
                    batteryPercentage: positiveBattery,
                    currentSpeed: 0.0,
                    activity: .stationary // Uses your official ActivityType enum case from AppModels
                )
                self.isAuthenticated = true
            }
        }
    }
    
    /// Authenticates credentials dynamically matching device contexts
        func attemptSecureLogin(username: String, password: String) {
            let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            // Updated to allow "noah" or "dash" with the new password
            if (cleanUsername == "noah" || cleanUsername == "dash") && password == "Dec102025" {
                let mockToken = UUID().uuidString
                if let tokenData = mockToken.data(using: .utf8) {
                    KeychainHelper.shared.save(tokenData, service: keychainIdentifier, account: "user_token")
                }
                
                UIDevice.current.isBatteryMonitoringEnabled = true
                let dynamicBattery = Int(UIDevice.current.batteryLevel * 100)
                let positiveBattery = dynamicBattery >= 0 ? dynamicBattery : 100
                
                DispatchQueue.main.async {
                    self.loginErrorMessage = nil
                    self.currentUserProfile = UserState(
                        id: "NODE-\(Int.random(in: 100...999))",
                        name: UIDevice.current.name,
                        latitude: 0.0,
                        longitude: 0.0,
                        batteryPercentage: positiveBattery,
                        currentSpeed: 0.0,
                        activity: .stationary
                    )
                    self.isAuthenticated = true
                }
            } else {
                DispatchQueue.main.async {
                    self.loginErrorMessage = "Invalid credentials."
                }
            }
        }
    
    /// Clears active credentials data safely without depending on static engine instances
    func performSecureLogout() {
        KeychainHelper.shared.delete(service: keychainIdentifier, account: "user_token")
        
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.currentUserProfile = nil
            self.loginErrorMessage = nil
        }
    }
}
