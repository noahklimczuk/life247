//
//  TelemetryDashboardDrawer.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-15.
//

import SwiftUI
import CoreLocation
import MapKit

struct TelemetryDashboardDrawer: View {
    @EnvironmentObject var authContext: SessionAuthContext
    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine
    @Binding var registeredZones: [GeofenceZone]
    
    @State private var activeTabPaneIndex = 0
    @StateObject private var canadaPostService = CanadaPostIntegrationService()
    @State private var postalSearchFieldText = ""
    
    // Emojis selection engine state variables
    @State private var chosenEmoji = "📍"
    private let emojiChoices = ["🏠", "🏢", "🏫", "🛒", "📍", "🌳", "Gym", "☕️"]
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(.systemGray4)).frame(width: 36, height: 5).padding(.vertical, 14)
            
            HStack(spacing: 0) {
                TabButton(title: "Circle", index: 0, activeIndex: $activeTabPaneIndex)
                TabButton(title: "Places", index: 1, activeIndex: $activeTabPaneIndex)
                TabButton(title: "Routes", index: 2, activeIndex: $activeTabPaneIndex)
            }
            .padding(.horizontal, 16)
            
            TabView(selection: $activeTabPaneIndex) {
                // TAB 0: CIRCLES OVERVIEW PANEL
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            Circle().fill(Color.purple.opacity(0.15)).frame(width: 48, height: 48)
                                .overlay(Text(String(authContext.currentUserProfile?.name.prefix(2) ?? "OP").uppercased()).foregroundColor(.purple).bold())
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(authContext.currentUserProfile?.name ?? "Operator")
                                        .font(.headline)
                                    Spacer()
                                    Text("🔋 \(authContext.currentUserProfile?.batteryPercentage ?? 100)%")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Image(systemName: "waveform.path.ecg").foregroundColor(.green)
                                    Text(trackingEngine.liveTrackingActive ? "Live Tracking Active" : "System Stationary")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    
                                    let rateInKPH = Int(max(0, (authContext.currentUserProfile?.currentSpeed ?? 0.0) * 3.6))
                                    Text("\(rateInKPH) km/h")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(.purple)
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                        
                        // Active System Tracked History Metrics View Wrapper
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Geofences Array Status (\(registeredZones.count))")
                                .font(.subheadline)
                                .bold()
                                .foregroundColor(.secondary)
                            
                            if registeredZones.isEmpty {
                                Text("No places monitored currently.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(registeredZones) { zone in
                                    HStack {
                                        Text(zone.emojiIcon).font(.title3)
                                        Text(zone.name).font(.callout).lineLimit(1)
                                        Spacer()
                                        Button(action: {
                                            trackingEngine.clearGeofenceZone(id: zone.id)
                                            registeredZones.removeAll(where: { $0.id == zone.id })
                                        }) {
                                            Image(systemName: "trash").foregroundColor(.red)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                    }
                    .padding(16)
                }
                .tag(0)
                
                // TAB 1: PLACES ADDRESS DISCOVERY CONTROLS VIEW
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Lookup Place Address via Canada Post...", text: $postalSearchFieldText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: postalSearchFieldText) { _, newVal in
                                if newVal.count > 2 {
                                    canadaPostService.executeRemoteSearchCall(text: newVal)
                                }
                            }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    // Custom Horizontal Emoji Selector Container View Layer
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Assign Place Icon Marker Emoji:")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 18)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(emojiChoices, id: \.self) { symbol in
                                    Text(symbol)
                                        .font(.title2)
                                        .padding(8)
                                        .background(Circle().fill(chosenEmoji == symbol ? Color.purple.opacity(0.2) : Color.clear))
                                        .overlay(Circle().stroke(chosenEmoji == symbol ? Color.purple : Color.clear, lineWidth: 2))
                                        .onTapGesture { chosenEmoji = symbol }
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                    
                    if canadaPostService.networkOperationActive {
                        ProgressView().tint(.purple).padding()
                    }
                    
                    List(canadaPostService.lookupResults) { match in
                        Button(action: { commitTargetGeofenceZone(from: match) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.text)
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundColor(.primary)
                                Text(match.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                .tag(1)
                
                // TAB 2: ROUTES HISTORY LIST LAYER
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Logged Driving Analytics History")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        if trackingEngine.recordedDrivesHistory.isEmpty {
                            Text("No driving operations archived yet.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(trackingEngine.recordedDrivesHistory) { drive in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("🚗 Automated Trip Drive").font(.subheadline).bold()
                                        Spacer()
                                        Text(drive.startTime, style: .date).font(.caption).foregroundColor(.secondary)
                                    }
                                    Text("Distance Covered: \(String(format: "%.2f", drive.totalDistanceMeters / 1000.0)) km")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color(.systemBackground))
    }
    
    // Core function explicitly included at struct level scope
    private func commitTargetGeofenceZone(from selection: CanadaPostSuggestion) {
        canadaPostService.processSelection(for: selection, currentSearchText: $postalSearchFieldText) { coordinatedMetrics in
            guard let coords = coordinatedMetrics else { return }
            DispatchQueue.main.async {
                let generatedZone = GeofenceZone(
                    id: UUID(),
                    name: selection.text,
                    latitude: coords.latitude,
                    longitude: coords.longitude,
                    radius: 150.0,
                    emojiIcon: self.chosenEmoji
                )
                self.registeredZones.append(generatedZone)
                self.trackingEngine.registerGeofenceHardwareBoundary(for: generatedZone)
                self.postalSearchFieldText = ""
                self.canadaPostService.lookupResults = []
                withAnimation { self.activeTabPaneIndex = 0 }
            }
        }
    }
}

// Fixed missing TabButton explicitly defined within file scope to guarantee visibility
struct TabButton: View {
    let title: String
    let index: Int
    @Binding var activeIndex: Int
    
    var body: some View {
        Button(action: { withAnimation { activeIndex = index } }) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(activeIndex == index ? .purple : .secondary)
                Rectangle()
                    .fill(activeIndex == index ? Color.purple : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
