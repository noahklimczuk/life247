//
//  life247App.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-08.
//

import SwiftUI

@main
struct life247App: App {
    // Instantiate our new session context and tracking state engines at the absolute root
    @StateObject private var authContext = SessionAuthContext()
    @StateObject private var trackingEngine = SystemTelemetryEngine() // Matches your project file name
    
    var body: some Scene {
        WindowGroup {
            RootRoutingView()
                .environmentObject(authContext)
                .environmentObject(trackingEngine)
        }
    }
}

// Automatically shifts screens based on the user's active session state
struct RootRoutingView: View {
    @EnvironmentObject var authContext: SessionAuthContext
    
    var body: some View {
        Group {
            if authContext.isAuthenticated {
                MainApplicationTelemetryWorkspace()
                    .transition(.opacity)
            } else {
                TelemetryLoadingView()
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: authContext.isAuthenticated)
    }
}
