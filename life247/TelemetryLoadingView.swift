//
//  TelemetryLoadingView.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-16.
//

import SwiftUI
import Combine

struct TelemetryLoadingView: View {
    @Binding var isFullyLoaded: Bool

    private let loadingDuration: TimeInterval = 4.0
    private let tickInterval: TimeInterval = 0.04

    /// SwiftUI-managed timer. Its subscription is owned by `.onReceive` and is
    /// cancelled automatically when the view leaves the hierarchy, so it can
    /// never fire into freed `@State` storage after the splash completes.
    private let progressTimer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    @State private var progress: Double = 0.0
    @State private var pulse = false
    @State private var iconAppeared = false

    private let accent = Color(red: 0.55, green: 0.36, blue: 1.0)
    private let accentSecondary = Color(red: 0.40, green: 0.70, blue: 1.0)

    var body: some View {
        ZStack {
            // Deep indigo gradient backdrop
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.03, blue: 0.12),
                    Color(red: 0.12, green: 0.06, blue: 0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Radar-style pulse emanating from the location marker
                ZStack {
                    ForEach(0..<3, id: \.self) { ring in
                        Circle()
                            .stroke(accent.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 120, height: 120)
                            .scaleEffect(pulse ? 2.2 : 0.55)
                            .opacity(pulse ? 0.0 : 0.6)
                            .animation(
                                .easeOut(duration: 2.4)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(ring) * 0.8),
                                value: pulse
                            )
                    }

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(0.95), accent.opacity(0.45)],
                                center: .center,
                                startRadius: 2,
                                endRadius: 60
                            )
                        )
                        .frame(width: 110, height: 110)
                        .shadow(color: accent.opacity(0.6), radius: 24, x: 0, y: 0)

                    Image(systemName: "location.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(iconAppeared ? 1.0 : 0.5)
                        .opacity(iconAppeared ? 1.0 : 0.0)
                }
                .frame(height: 260)

                Spacer().frame(height: 32)

                // Wordmark + tagline
                VStack(spacing: 8) {
                    Text("Life 24/7")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, accent.opacity(0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Keeping your circle connected")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                // Slim gradient progress bar with rotating status text
                VStack(spacing: 12) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 6)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [accent, accentSecondary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * progress), height: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 60)

                    Text(statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: statusText)
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            pulse = true
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                iconAppeared = true
            }
        }
        // Drives the visible progress from 0 to 100% over `loadingDuration`.
        // `.onReceive` owns the subscription, so the timer stops the moment the
        // splash is removed from the hierarchy.
        .onReceive(progressTimer) { _ in
            guard progress < 1.0 else { return }
            progress = min(1.0, progress + tickInterval / loadingDuration)
            if progress >= 1.0 {
                withAnimation { isFullyLoaded = true }
            }
        }
    }

    /// Friendly status message that advances with loading progress.
    private var statusText: String {
        switch progress {
        case ..<0.35: return "Connecting to your circle…"
        case ..<0.70: return "Syncing live locations…"
        case ..<1.0:  return "Almost there…"
        default:      return "Ready"
        }
    }
}

struct TelemetryLoadingView_Previews: PreviewProvider {
    static var previews: some View {
        // Keeps the view layout fully functional inside the Xcode preview canvas
        TelemetryLoadingView(isFullyLoaded: .constant(false))
    }
}
