//
//  SessionAuthContext.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-18.
//

import Foundation
import CoreLocation
import Combine

// Model to hold the active user's tracking profile details
struct UserProfileNode {
    var name: String
    var coordinate: CLLocationCoordinate2D
    var batteryPercentage: Int
}

class SessionAuthContext: ObservableObject {
    // Starting as false means every fresh boot defaults straight to the loading/login views
    @Published var isAuthenticated: Bool = false
    @Published var currentUserProfile: UserProfileNode? = nil
    
    // Changes state flags to dynamically push the user into the main workspace
    func performSecureLogin(name: String, coordinate: CLLocationCoordinate2D) {
        DispatchQueue.main.async {
            self.currentUserProfile = UserProfileNode(
                name: name,
                coordinate: coordinate,
                batteryPercentage: 100
            )
            self.isAuthenticated = true
        }
    }
    
    // Instantly drops user back out to the loading layout when Log Out is clicked
    func performSecureLogout() {
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.currentUserProfile = nil
        }
    }
}
