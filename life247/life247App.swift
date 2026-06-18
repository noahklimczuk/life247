//
//  life247App.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-08.
//

import SwiftUI

@main
struct life247App: App {
    // Instantiate session context at the absolute root
    @StateObject private var authContext = SessionAuthContext()
    
    var body: some Scene {
        WindowGroup {
            MainAppInterfaceHub() // Uses coordinated entry point to delegate login/workspace routing pipeline
                .environmentObject(authContext)
                .environmentObject(BackgroundTrackingEngine.shared) // Injecting the globally shared singleton instance directly
        }
    }
}
