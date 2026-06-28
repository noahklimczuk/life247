//
//  life247App.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-08.
//

import SwiftUI

@main
struct life247App: App {
    @StateObject private var authContext = SessionAuthContext()

    init() {
        UserDefaults.registerLife247Defaults()
    }

    var body: some Scene {
        WindowGroup {
            RootRouterView() // Points to unified root router handling the splash sequence
                .environmentObject(authContext)
                .environmentObject(BackgroundTrackingEngine.shared)
                .environmentObject(CircleSyncService.shared)
        }
    }
}
