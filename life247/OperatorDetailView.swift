//
//  OperatorDetailView.swift
//  life247
//

import SwiftUI
import Combine
import CoreLocation
import MapKit

/// Detailed account view for an operator: name, reverse-geocoded address and a
/// live "time at location" counter. Presented from the Circle tab and from the
/// map's current-user marker.
struct OperatorDetailView: View {
    let profile: UserState
    /// When true, the operator is the signed-in user on this device and we use
    /// the live local GPS fix; otherwise we show the member's shared position.
    var isCurrentUser: Bool = true

    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine
    @Environment(\.dismiss) private var dismiss
    @State private var resolvedAddress = "Resolving address…"
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// The operator's current position: the live GPS fix for this device's user,
    /// or the position shared by the member through the circle database.
    private var currentCoordinate: CLLocationCoordinate2D {
        if isCurrentUser {
            return trackingEngine.liveLocation ?? profile.coordinate
        }
        return profile.coordinate
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        MemberAvatar(name: profile.name, isCharging: profile.isCharging, size: 64, image: AvatarCache.image(forBase64: profile.avatarBase64))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name).font(.title3).bold()
                            Text(statusLine)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                if profile.isSOS {
                    Section {
                        Label("SOS active — \(profile.name) needs help", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.red)
                    }
                }

                Section("Current Location") {
                    if let place = CircleSyncService.shared.place(for: profile) {
                        detailRow(icon: "house.fill", title: "Place", value: "\(place.emojiIcon.isEmpty ? "📍" : place.emojiIcon)  \(place.name)")
                    }
                    detailRow(icon: "mappin.and.ellipse", title: "Address", value: resolvedAddress)
                    detailRow(icon: "clock", title: "Time at location", value: dwellText)
                    detailRow(icon: "location",
                              title: "Coordinates",
                              value: String(format: "%.5f, %.5f", currentCoordinate.latitude, currentCoordinate.longitude))
                }
            }
            .navigationTitle("Operator Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .onAppear(perform: resolveAddress)
        .onChange(of: trackingEngine.liveLocation?.latitude) { _, _ in
            if isCurrentUser { resolveAddress() }
        }
        .onChange(of: trackingEngine.liveLocation?.longitude) { _, _ in
            if isCurrentUser { resolveAddress() }
        }
    }

    /// Battery / charging / movement summary shown under the operator's name.
    private var statusLine: String {
        var parts: [String] = []
        parts.append("\(profile.batteryPercentage)%\(profile.isCharging ? " ⚡️" : "")")
        if profile.activity == .driving {
            parts.append("Driving \(UnitFormatter.speedString(metersPerSecond: profile.currentSpeed))")
        } else {
            parts.append(profile.activity.rawValue)
        }
        return parts.joined(separator: "  •  ")
    }

    /// When the operator settled at their current location. For this device's
    /// user we use the engine's persisted anchor (survives restarts); for the
    /// partner we use the value they shared through the circle.
    private var atLocationSince: Date {
        isCurrentUser ? trackingEngine.atLocationSince : profile.atLocationSince
    }

    /// Human-readable elapsed time since the operator arrived at the location.
    private var dwellText: String {
        let elapsed = max(0, now.timeIntervalSince(atLocationSince))
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60

        if hours > 0 { return String(format: "%dh %02dm %02ds", hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, seconds) }
        return String(format: "%ds", seconds)
    }

    @ViewBuilder
    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.purple)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundColor(.secondary)
                Text(value).font(.body)
            }
        }
        .padding(.vertical, 2)
    }

    private func resolveAddress() {
        let coordinate = currentCoordinate
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            resolvedAddress = "Address unavailable"
            return
        }

        Task {
            let address = try? await request.mapItems.first?.address?.fullAddress
            await MainActor.run {
                self.resolvedAddress = address ?? "Address unavailable"
            }
        }
    }
}
