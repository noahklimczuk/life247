//
//  TelemetryLoadingView.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-16.
//

import SwiftUI

struct TelemetryLoadingView: View {
    @Binding var isFullyLoaded: Bool
    
    @State private var progress: Double = 0.01
    @State private var isAnimatingSpinner = false
    
    var body: some View {
        ZStack {
            // Dark purple/plum layout background matching the app's style
            Color(red: 0.10, green: 0.05, blue: 0.18)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Icon Container with a subtle neon purple glow
                ZStack {
                    Circle()
                        .fill(Color(red: 0.15, green: 0.05, blue: 0.25))
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.purple.opacity(0.3), radius: 15, x: 0, y: 5)
                    
                    Image(systemName: "pin.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundColor(.purple)
                }
                
                // Updated layout typography
                VStack(spacing: 12) {
                    Text("Life 24/7")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    // Core text string updated to "Initializing..."
                    Text("Initializing system setup... (\(Int(progress * 100))%)")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Custom Ring Loader matching the telemetry tint
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 54, height: 54)
                    
                    Circle()
                        .trim(from: 0, to: 0.3)
                        // Fixed syntax using a nested StrokeStyle object
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 54, height: 54)
                        .rotationEffect(Angle(degrees: isAnimatingSpinner ? 360 : 0))
                        .onAppear {
                            withAnimation(Animation.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                isAnimatingSpinner = true
                            }
                            
                            // Simulate completing the splash sequence layout safely for testing
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                withAnimation {
                                    isFullyLoaded = true
                                }
                            }
                        }
                }
                .padding(.bottom, 20)
                
                // Destructive/Cancel styling aligned with your side menu forms
                
            }
        }
    }
}

struct TelemetryLoadingView_Previews: PreviewProvider {
    static var previews: some View {
        // Keeps the view layout fully functional inside the Xcode preview canvas
        TelemetryLoadingView(isFullyLoaded: .constant(false))
    }
}
