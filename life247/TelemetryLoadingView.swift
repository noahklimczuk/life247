//
//  TelemetryLoadingView.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-16.
//

import SwiftUI

struct TelemetryLoadingView: View {
    @State private var isAnimating = false
    @State private var scanRotation: Double = 0.0
    
    var body: some View {
        ZStack {
            // High-tech deep space background gradient
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.03, blue: 0.06), Color(red: 0.08, green: 0.06, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Background Coordinate Grid Overlay
            GeometryReader { geo in
                Path { path in
                    let steps = 4
                    // Horizontal lines
                    for i in 1..<steps {
                        let y = geo.size.height / CGFloat(steps) * CGFloat(i)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    // Vertical lines
                    for i in 1..<steps {
                        let x = geo.size.width / CGFloat(steps) * CGFloat(i)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                }
                .stroke(Color.purple.opacity(0.04), lineWidth: 1)
            }
            
            // RADAR ENGINE ENGINE LAYER
            ZStack {
                // Outer Telemetry Border Ring
                Circle()
                    .stroke(Color.purple.opacity(0.1), lineWidth: 1)
                    .frame(width: 280, height: 280)
                
                // --- CONCENTRIC RADAR PING WAVES ---
                // Wave 1
                Circle()
                    .stroke(Color.purple.opacity(0.35), lineWidth: 2)
                    .frame(width: isAnimating ? 280 : 40, height: isAnimating ? 280 : 40)
                    .scaleEffect(isAnimating ? 1.0 : 0.1)
                    .opacity(isAnimating ? 0.0 : 1.0)
                
                // Wave 2 (Offset delayed wave)
                Circle()
                    .stroke(Color.purple.opacity(0.25), lineWidth: 1.5)
                    .frame(width: isAnimating ? 280 : 40, height: isAnimating ? 280 : 40)
                    .scaleEffect(isAnimating ? 1.0 : 0.1)
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(0.7), value: isAnimating)
                
                // Wave 3 (Far offset wave)
                Circle()
                    .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                    .frame(width: isAnimating ? 280 : 40, height: isAnimating ? 280 : 40)
                    .scaleEffect(isAnimating ? 1.0 : 0.1)
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(1.4), value: isAnimating)
                
                // Rotating Sweep Line
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.purple.opacity(0.25), .clear],
                            center: .center,
                            startAngle: .degrees(90),
                            endAngle: .degrees(0)
                        )
                    )
                    .frame(width: 280, height: 280)
                    .rotationEffect(.degrees(scanRotation))
                
                // --- CORE ANCHOR ELEMENT ---
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 54, height: 54)
                    
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 40, height: 40)
                        .shadow(color: .purple.opacity(0.6), radius: 10)
                    
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            // STATUS STRINGS FOOTER
            VStack(spacing: 8) {
                Spacer()
                
                Text("LOCKING COORDINATES")
                    .font(.system(.caption, design: .monospaced))
                    .bold()
                    .foregroundColor(.purple)
                    .tracking(3)
                
                Text("Resolving geofence metrology systems...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 50)
        }
        .onAppear {
            // Trigger the expanding radar waves
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
            // Trigger the infinite rotating radar sweep
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                scanRotation = 360.0
            }
        }
    }
}

// MARK: - SwiftUI Preview Provider
#Preview {
    TelemetryLoadingView()
}
