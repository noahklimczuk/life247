//
//  PrimaryInterfaceLayout.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-15.
//

import SwiftUI

/// Single entry point for the app. Shows one splash sequence, then routes to
/// the authenticated workspace or the login screen via `MainAppInterfaceHub`.
struct RootRouterView: View {
    @EnvironmentObject var authContext: SessionAuthContext
    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine
    @State private var splashCompleted = false

    var body: some View {
        ZStack {
            if !splashCompleted {
                TelemetryLoadingView(isFullyLoaded: $splashCompleted)
                    .transition(.opacity)
            } else {
                MainAppInterfaceHub()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: splashCompleted)
        .onAppear {
            trackingEngine.initializeSystemHardwareAccess()
        }
    }
}
