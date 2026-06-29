//
//  SafetyAndTripViews.swift
//  life247
//
//  Phase 3 surfaces: a per-trip detail with the recorded route drawn on a map,
//  and a Safety pane with the SOS broadcast control and a circle check-in.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Trip detail

/// Shows a single recorded drive: the breadcrumb route on a map plus distance,
/// duration and top-speed stats.
struct TripDetailView: View {
    let drive: HistoricalRouteDrive

    @Environment(\.dismiss) private var dismiss

    private var routeRegion: MKCoordinateRegion {
        guard let first = drive.breadcrumbs.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832),
                                      span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in drive.breadcrumbs {
            minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude); maxLon = max(maxLon, point.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.005, (maxLat - minLat) * 1.4),
                                    longitudeDelta: max(0.005, (maxLon - minLon) * 1.4))
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(initialPosition: .region(routeRegion)) {
                    if drive.breadcrumbs.count > 1 {
                        MapPolyline(coordinates: drive.breadcrumbs)
                            .stroke(drive.isDriving ? .blue : .teal, lineWidth: 5)
                    }
                    if let start = drive.breadcrumbs.first {
                        Annotation("Start", coordinate: start) {
                            routePoint(color: .green, symbol: "flag.fill")
                        }
                    }
                    if let end = drive.breadcrumbs.last {
                        Annotation("End", coordinate: end) {
                            routePoint(color: .red, symbol: "flag.checkered")
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                statsBar
            }
            .navigationTitle("Trip Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statsBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Label(drive.modeLabel, systemImage: drive.modeSymbol)
                    .font(.caption.bold())
                    .foregroundColor(drive.isDriving ? .blue : .teal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill((drive.isDriving ? Color.blue : Color.teal).opacity(0.15)))
                Text(drive.startTime, format: .dateTime.weekday().month().day().hour().minute())
                    .font(.subheadline).foregroundColor(.secondary)
            }

            HStack(spacing: 0) {
                stat(title: "Distance", value: UnitFormatter.distanceString(meters: drive.totalDistanceMeters), icon: "ruler")
                Divider().frame(height: 36)
                stat(title: "Duration", value: UnitFormatter.durationString(seconds: drive.duration), icon: "clock")
                Divider().frame(height: 36)
                stat(title: "Top Speed", value: UnitFormatter.speedString(metersPerSecond: drive.maxSpeedMetersPerSecond), icon: "speedometer")
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    private func stat(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.headline).foregroundColor(.purple)
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func routePoint(color: Color, symbol: String) -> some View {
        ZStack {
            Circle().fill(color).frame(width: 28, height: 28).shadow(radius: 2)
            Image(systemName: symbol).font(.caption).foregroundColor(.white)
        }
    }
}

// MARK: - Safety pane

/// Drawer pane with the SOS broadcast toggle, a circle check-in, and a summary of
/// each member's current safety status.
struct SafetyPaneView: View {
    let roster: [UserState]
    let currentUsername: String

    @EnvironmentObject var circleSync: CircleSyncService
    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine

    @State private var showSOSConfirm = false
    @State private var checkInMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Safety")
                    .font(.title3).bold()

                sosCard
                checkInCard

                Text("Circle Status")
                    .font(.headline)

                ForEach(roster) { member in
                    statusRow(member)
                }
            }
            .padding(16)
        }
        .alert("Send SOS to your circle?", isPresented: $showSOSConfirm) {
            Button("Send SOS", role: .destructive) { circleSync.setSOS(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your circle will be alerted with your live location until you cancel.")
        }
    }

    private var sosCard: some View {
        VStack(spacing: 12) {
            if circleSync.isBroadcastingSOS {
                Label("SOS is active", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundColor(.red)
                Text("Your circle has been alerted with your location.")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(role: .cancel) { circleSync.setSOS(false) } label: {
                    Text("Cancel SOS")
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray))
                }
            } else {
                Button { showSOSConfirm = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "sos.circle.fill").font(.system(size: 34))
                        Text("Send SOS").font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 96)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.red))
                }
                Text("Instantly alert your circle with your live location.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }

    private var checkInCard: some View {
        VStack(spacing: 8) {
            Button(action: sendCheckIn) {
                Label("Check in", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.green))
            }
            if let message = checkInMessage {
                Text(message).font(.caption).foregroundColor(.secondary)
            } else {
                Text("Let your circle know you're safe — posts your location to the chat.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }

    private func statusRow(_ member: UserState) -> some View {
        let isMe = !currentUsername.isEmpty && member.username == currentUsername
        let place = circleSync.place(for: member)
        return HStack(spacing: 12) {
            MemberAvatar(name: member.name, isCharging: member.isCharging, size: 40, image: AvatarCache.image(forBase64: member.avatarBase64))
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name + (isMe ? " (You)" : "")).font(.subheadline).bold()
                Text(place.map { "at \($0.name)" } ?? statusText(member))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if member.isSOS {
                Label("SOS", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.bold()).foregroundColor(.red)
            } else {
                Image(systemName: member.batteryPercentage < 20 && !member.isCharging ? "battery.25" : "checkmark.circle.fill")
                    .foregroundColor(member.batteryPercentage < 20 && !member.isCharging ? .red : .green)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func statusText(_ member: UserState) -> String {
        switch member.activity {
        case .driving: return "Driving \(UnitFormatter.speedString(metersPerSecond: member.currentSpeed))"
        case .walking: return "Walking"
        case .stationary: return "\(member.batteryPercentage)% battery"
        }
    }

    private func sendCheckIn() {
        let coordinate = trackingEngine.liveLocation
        Task {
            var text = "📍 Checked in — I'm safe."
            if let coordinate {
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                if let request = MKReverseGeocodingRequest(location: location),
                   let address = try? await request.mapItems.first?.address?.fullAddress, !address.isEmpty {
                    text = "📍 Checked in at \(address) — I'm safe."
                }
            }
            await MainActor.run {
                CircleChatService.shared.send(text)
                checkInMessage = "Checked in and posted to chat."
            }
        }
    }
}
