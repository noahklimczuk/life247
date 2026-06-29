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

                // Restore the operator's display name and login handle from the saved session
                let restoredName = self.savedDisplayName() ?? UIDevice.current.name
                let restoredUsername = self.savedUsername() ?? restoredName.lowercased()
                let restoredAvatar = self.loadSelfAvatar()

                // ALWAYS publish UI state updates safely to the Main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.currentUserProfile = UserState(
                        id: "NODE-\(Int.random(in: 100...999))",
                        name: restoredName,
                        username: restoredUsername,
                        latitude: lastLat,
                        longitude: lastLon,
                        batteryPercentage: positiveBattery,
                        currentSpeed: 0.0,
                        activity: .stationary,
                        avatarBase64: restoredAvatar
                    )
                    self.isAuthenticated = true

                    // Keep live battery telemetry running for restored sessions too
                    BackgroundTrackingEngine.shared.startLiveBatteryMonitoring(authContext: self)

                    // Begin sharing this operator's live position with the circle
                    if let profile = self.currentUserProfile {
                        RelayPushService.shared.currentUserName = profile.name
                        CircleSyncService.shared.start(id: profile.id, name: profile.name, username: restoredUsername)
                        CircleSyncService.shared.updateAvatar(restoredAvatar)
                        CircleChatService.shared.start(senderId: restoredUsername, senderName: profile.name)
                        PlacesSyncService.shared.start()
                        TripsSyncService.shared.start(username: restoredUsername)
                    }
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

            // Persist the operator's display name (defaulting to a capitalized
            // handle) plus the login handle so both survive session restores.
            let displayName = self.savedDisplayName() ?? cleanUsername.capitalized
            if let nameData = displayName.data(using: .utf8) {
                KeychainHelper.shared.save(nameData, service: keychainIdentifier, account: "user_name")
            }
            if let usernameData = cleanUsername.data(using: .utf8) {
                KeychainHelper.shared.save(usernameData, service: keychainIdentifier, account: "user_username")
            }
            let savedAvatar = self.loadSelfAvatar()

            UIDevice.current.isBatteryMonitoringEnabled = true
            let positiveBattery = BackgroundTrackingEngine.batteryPercentage(from: UIDevice.current.batteryLevel)

            let lastLat = BackgroundTrackingEngine.shared.liveLocation?.latitude ?? 43.6532
            let lastLon = BackgroundTrackingEngine.shared.liveLocation?.longitude ?? -79.3832
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.loginErrorMessage = nil
                self.currentUserProfile = UserState(
                    id: "NODE-\(Int.random(in: 100...999))",
                    name: displayName,
                    username: cleanUsername,
                    latitude: lastLat,
                    longitude: lastLon,
                    batteryPercentage: positiveBattery,
                    currentSpeed: 0.0,
                    activity: .stationary,
                    avatarBase64: savedAvatar
                )
                self.isAuthenticated = true
                
                // Boot live telemetry battery tracking directly upon login success
                BackgroundTrackingEngine.shared.startLiveBatteryMonitoring(authContext: self)

                // Begin sharing this operator's live position with the circle
                if let profile = self.currentUserProfile {
                    RelayPushService.shared.currentUserName = profile.name
                    CircleSyncService.shared.start(id: profile.id, name: profile.name, username: cleanUsername)
                    CircleSyncService.shared.updateAvatar(savedAvatar)
                    CircleChatService.shared.start(senderId: cleanUsername, senderName: profile.name)
                    PlacesSyncService.shared.start()
                    TripsSyncService.shared.start(username: cleanUsername)
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.loginErrorMessage = "Invalid credentials."
            }
        }
    }
    
    /// Reads the operator's saved display name from secure storage, if present.
    private func savedDisplayName() -> String? {
        guard let data = KeychainHelper.shared.read(service: keychainIdentifier, account: "user_name"),
              let name = String(data: data, encoding: .utf8), !name.isEmpty else { return nil }
        return name
    }

    /// Reads the operator's saved login handle from secure storage, if present.
    private func savedUsername() -> String? {
        guard let data = KeychainHelper.shared.read(service: keychainIdentifier, account: "user_username"),
              let username = String(data: data, encoding: .utf8), !username.isEmpty else { return nil }
        return username
    }

    /// Loads the locally-stored profile picture (base64 JPEG), if the user set one.
    private func loadSelfAvatar() -> String? {
        let stored = UserDefaults.standard.string(forKey: AppSettingsKeys.selfAvatar)
        return (stored?.isEmpty == false) ? stored : nil
    }

    /// Updates the operator's display name everywhere: local profile, secure
    /// storage, and the live circle/chat/relay identity so the partner sees it.
    func updateDisplayName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let nameData = trimmed.data(using: .utf8) {
            KeychainHelper.shared.save(nameData, service: keychainIdentifier, account: "user_name")
        }
        currentUserProfile?.name = trimmed
        RelayPushService.shared.currentUserName = trimmed
        CircleSyncService.shared.updateDisplayName(trimmed)
        CircleChatService.shared.updateDisplayName(trimmed)
    }

    /// Sets (or clears, when nil) the operator's profile picture, persisting it
    /// locally and publishing it to the circle so the partner sees it too.
    func updateAvatar(_ image: UIImage?) {
        let base64 = image.flatMap { AvatarCache.encode($0) }
        if let base64 {
            UserDefaults.standard.set(base64, forKey: AppSettingsKeys.selfAvatar)
        } else {
            UserDefaults.standard.removeObject(forKey: AppSettingsKeys.selfAvatar)
        }
        currentUserProfile?.avatarBase64 = base64
        CircleSyncService.shared.updateAvatar(base64)
    }

    /// Clears active credentials data safely without depending on static engine instances
    func performSecureLogout() {
        KeychainHelper.shared.delete(service: keychainIdentifier, account: "user_token")
        KeychainHelper.shared.delete(service: keychainIdentifier, account: "user_name")
        KeychainHelper.shared.delete(service: keychainIdentifier, account: "user_username")
        CircleSyncService.shared.stop()
        CircleChatService.shared.stop()
        PlacesSyncService.shared.stop()
        TripsSyncService.shared.stop()
        RelayPushService.shared.currentUserName = nil
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isAuthenticated = false
            self.currentUserProfile = nil
            self.loginErrorMessage = nil
        }
    }
}
