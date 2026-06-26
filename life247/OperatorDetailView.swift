//
//  OperatorDetailView.swift
//  life247
//

import SwiftUI
import Combine
import CoreLocation

/// Detailed account view for an operator: name, reverse-geocoded address and a
/// live "time at location" counter. Presented from the Circle tab and from the
/// map's current-user marker.
struct OperatorDetailView: View {
    let profile: UserState

    @Environment(\.dismiss) private var dismiss
    @State private var resolvedAddress = "Resolving address…"
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.15)).frame(width: 64, height: 64)
                            Text(String(profile.name.prefix(2)).uppercased())
                                .font(.title2).bold().foregroundColor(.blue)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name).font(.title3).bold()
                            Text("🔋 \(profile.batteryPercentage)%  •  \(profile.activity.rawValue)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                Section("Current Location") {
                    detailRow(icon: "mappin.and.ellipse", title: "Address", value: resolvedAddress)
                    detailRow(icon: "clock", title: "Time at location", value: dwellText)
                    detailRow(icon: "location",
                              title: "Coordinates",
                              value: String(format: "%.5f, %.5f", profile.latitude, profile.longitude))
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
    }

    /// Human-readable elapsed time since the operator arrived at the location.
    private var dwellText: String {
        let elapsed = max(0, now.timeIntervalSince(profile.atLocationSince))
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
        let location = CLLocation(latitude: profile.latitude, longitude: profile.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            guard let placemark = placemarks?.first else {
                DispatchQueue.main.async { self.resolvedAddress = "Address unavailable" }
                return
            }

            let street = [placemark.subThoroughfare, placemark.thoroughfare]
                .compactMap { $0 }
                .joined(separator: " ")
            let parts = [street, placemark.locality, placemark.administrativeArea, placemark.postalCode]
                .compactMap { $0 }
                .filter { !$0.isEmpty }

            DispatchQueue.main.async {
                self.resolvedAddress = parts.isEmpty ? "Address unavailable" : parts.joined(separator: ", ")
            }
        }
    }
}
