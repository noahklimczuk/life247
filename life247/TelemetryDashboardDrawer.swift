//
//  TelemetryDashboardDrawer.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-15.
//

import SwiftUI
import MapKit

struct TelemetryDashboardDrawer: View {
    @EnvironmentObject var authContext: SessionAuthContext
    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine
    @EnvironmentObject var circleSync: CircleSyncService
    @Binding var registeredZones: [GeofenceZone]
    
    @State private var activeTabPaneIndex = 0
    @StateObject private var appleLookupService = AppleAddressLookupService()
    @State private var postalSearchFieldText = ""

    @State private var selectedMember: UserState?
    @State private var pendingPlace: PendingPlace?
    @State private var editingZone: GeofenceZone?
    @State private var selectedTrip: HistoricalRouteDrive?

    /// All circle members to display, ensuring the current operator always
    /// appears even before their first position reaches the shared database.
    private var circleRoster: [UserState] {
        var list = circleSync.members
        if let me = authContext.currentUserProfile,
           !list.contains(where: { $0.name.lowercased() == me.name.lowercased() }) {
            list.insert(me, at: 0)
        }
        return list
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(.systemGray4)).frame(width: 36, height: 5).padding(.vertical, 14)
            
            HStack(spacing: 0) {
                TabButton(title: "Circle", index: 0, activeIndex: $activeTabPaneIndex)
                TabButton(title: "Places", index: 1, activeIndex: $activeTabPaneIndex)
                TabButton(title: "Trips", index: 2, activeIndex: $activeTabPaneIndex)
                TabButton(title: "Safety", index: 3, activeIndex: $activeTabPaneIndex)
            }
            .padding(.horizontal, 16)
            
            TabView(selection: $activeTabPaneIndex) {
                // TAB 0: CIRCLES OVERVIEW PANEL
                ScrollView {
                    VStack(spacing: 12) {
                        HStack {
                            Text("People")
                                .font(.title3).bold()
                            Spacer()
                            Text("\(circleRoster.count)")
                                .font(.subheadline).bold()
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                        .padding(.horizontal, 2)

                        ForEach(circleRoster) { member in
                            let isMe = member.name.lowercased() == (authContext.currentUserProfile?.name.lowercased() ?? "")
                            CircleMemberRow(
                                member: member,
                                isCurrentUser: isMe,
                                isTracking: trackingEngine.liveTrackingActive
                            )
                            .onTapGesture { selectedMember = member }
                        }

                        if circleRoster.isEmpty {
                            Text("No circle members online yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(16)
                }
                .tag(0)
                .sheet(item: $selectedMember) { member in
                    let isMe = member.name.lowercased() == (authContext.currentUserProfile?.name.lowercased() ?? "")
                    OperatorDetailView(profile: member, isCurrentUser: isMe)
                }
                
                // TAB 1: PLACES — SEARCH, SAVE (WITH NAME), EDIT
                placesPane
                    .tag(1)
                    .sheet(item: $pendingPlace) { pending in
                        PlaceEditorView(
                            mode: .add(coordinate: pending.coordinate, suggestedName: pending.suggestedName),
                            onSave: addPlace
                        )
                        .presentationDetents([.medium, .large])
                    }
                    .sheet(item: $editingZone) { zone in
                        PlaceEditorView(
                            mode: .edit(zone: zone),
                            onSave: applyPlaceEdit,
                            onDelete: deletePlace
                        )
                        .presentationDetents([.medium, .large])
                    }
                
                // TAB 2: DRIVING — TRIP HISTORY WITH TAP-THROUGH DETAIL
                drivingPane
                    .tag(2)
                    .sheet(item: $selectedTrip) { trip in
                        TripDetailView(drive: trip)
                    }

                // TAB 3: SAFETY — SOS, CHECK-IN, CIRCLE STATUS
                SafetyPaneView(
                    roster: circleRoster,
                    currentUserName: authContext.currentUserProfile?.name ?? ""
                )
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Driving pane

    private var drivingPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Trips")
                        .font(.title3).bold()
                    Spacer()
                    Text("\(trackingEngine.recordedDrivesHistory.count)")
                        .font(.subheadline).bold()
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                }

                if trackingEngine.recordedDrivesHistory.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "car")
                            .font(.title).foregroundColor(.secondary)
                        Text("No trips yet")
                            .font(.subheadline).bold()
                        Text("Trips are recorded automatically when you start walking or driving.")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(trackingEngine.recordedDrivesHistory) { drive in
                        Button(action: { selectedTrip = drive }) {
                            tripRow(drive)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tripRow(_ drive: HistoricalRouteDrive) -> some View {
        let tint: Color = drive.isDriving ? .blue : .teal
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 46, height: 46)
                Image(systemName: drive.modeSymbol).foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(drive.modeLabel)
                        .font(.caption2.bold())
                        .foregroundColor(tint)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.15)))
                    Text(drive.startTime, format: .dateTime.weekday().month().day().hour().minute())
                        .font(.subheadline).bold().lineLimit(1)
                }
                HStack(spacing: 10) {
                    Label(UnitFormatter.distanceString(meters: drive.totalDistanceMeters), systemImage: "ruler")
                    Label(UnitFormatter.durationString(seconds: drive.duration), systemImage: "clock")
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Places pane

    private var placesPane: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search an address to add a place", text: $postalSearchFieldText)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: postalSearchFieldText) {
                        if appleLookupService.isProgrammaticUpdate {
                            appleLookupService.isProgrammaticUpdate = false
                            return
                        }
                        if postalSearchFieldText.count > 2 {
                            appleLookupService.executeRemoteSearchCall(text: postalSearchFieldText)
                        }
                    }
                if !postalSearchFieldText.isEmpty {
                    Button {
                        postalSearchFieldText = ""
                        appleLookupService.lookupResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if !appleLookupService.lookupResults.isEmpty {
                List(appleLookupService.lookupResults, id: \.self) { match in
                    Button(action: { beginAddingPlace(from: match) }) {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse").foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.title).font(.subheadline).bold().foregroundColor(.primary)
                                Text(match.subtitle).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                savedPlacesList
            }

            if appleLookupService.networkOperationActive {
                ProgressView().tint(.purple).padding(.bottom, 8)
            }
        }
    }

    private var savedPlacesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Saved Places")
                        .font(.title3).bold()
                    Spacer()
                    Text("\(registeredZones.count)")
                        .font(.subheadline).bold()
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
                .padding(.horizontal, 2)

                if registeredZones.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "mappin.slash")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("No places yet")
                            .font(.subheadline).bold()
                        Text("Search an address above to save a place like Home or Work.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(registeredZones) { zone in
                        Button(action: { editingZone = zone }) {
                            placeRow(zone)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
    }

    private func placeRow(_ zone: GeofenceZone) -> some View {
        HStack(spacing: 14) {
            Text(zone.emojiIcon.isEmpty ? "📍" : zone.emojiIcon)
                .font(.title2)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.purple.opacity(0.15)))

            VStack(alignment: .leading, spacing: 3) {
                Text(zone.name).font(.headline).lineLimit(1)
                Text("\(Int(zone.radius)) m radius")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Place actions

    private func beginAddingPlace(from selection: MKLocalSearchCompletion) {
        appleLookupService.isProgrammaticUpdate = true
        postalSearchFieldText = selection.title

        let searchRequest = MKLocalSearch.Request(completion: selection)
        MKLocalSearch(request: searchRequest).start { response, _ in
            guard let coords = response?.mapItems.first?.location.coordinate else { return }
            DispatchQueue.main.async {
                self.postalSearchFieldText = ""
                self.appleLookupService.lookupResults = []
                self.pendingPlace = PendingPlace(coordinate: coords, suggestedName: selection.title)
            }
        }
    }

    private func addPlace(_ zone: GeofenceZone) {
        registeredZones.append(zone)
        trackingEngine.registerGeofenceHardwareBoundary(for: zone)
    }

    private func applyPlaceEdit(_ zone: GeofenceZone) {
        if let index = registeredZones.firstIndex(where: { $0.id == zone.id }) {
            registeredZones[index] = zone
        }
        trackingEngine.updateGeofenceZone(zone)
    }

    private func deletePlace(_ zone: GeofenceZone) {
        trackingEngine.clearGeofenceZone(id: zone.id)
        registeredZones.removeAll(where: { $0.id == zone.id })
    }
}

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
