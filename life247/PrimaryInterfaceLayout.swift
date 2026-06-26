//
//  PrimaryInterfaceLayout.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-15.
//

import SwiftUI

struct RootRouterView: View {
    @EnvironmentObject var authContext: SessionAuthContext
    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine
    @State private var renderingSplashSequence = true
    
    var body: some View {
        ZStack {
            if renderingSplashSequence {
                SplashGraphicDisplayView(isActive: $renderingSplashSequence)
            } else {
                MainAppInterfaceHub() // Routes smoothly down to Core Telemetry spaces
            }
        }
        .onAppear {
            trackingEngine.initializeSystemHardwareAccess()
        }
    }
}

struct SplashGraphicDisplayView: View {
    @Binding var isActive: Bool
    @State private var scaleModifier: CGFloat = 0.85
    @State private var dynamicOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.purple.opacity(0.2), lineWidth: 4).frame(width: 100, height: 100)
                    Circle().fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 70, height: 70)
                }
                .scaleEffect(scaleModifier)
                Text("life247").font(.system(size: 32, weight: .bold, design: .rounded)).tracking(1)
            }
            .opacity(dynamicOpacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                scaleModifier = 1.0; dynamicOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    dynamicOpacity = 0.0; isActive = false
                }
            }
        }
    }
}
