//
//  MainApplicationTelemetryWorkspace.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-15.
//

import SwiftUI
import MapKit

// Clean local representation for mapping marker pins safely
struct LocalMapMarkerIdentifier: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let isCurrentUser: Bool
    var isCharging: Bool = false
    var batteryPercentage: Int = 100
    var avatarBase64: String? = nil
}

struct MainApplicationTelemetryWorkspace: View {
    @EnvironmentObject var authContext: SessionAuthContext
    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine
    @EnvironmentObject var circleSync: CircleSyncService
    
    @State private var viewportCamera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var contextualSheetPresented = true
    
    // Controls the visible open state of the side drawer panel
    @State private var showHamburgerMenu = false
    @State private var showUserDetailSheet = false
    @State private var selectedRemoteMember: UserState?
    @State private var showChat = false
    @State private var showSOSConfirm = false

    @AppStorage(AppSettingsKeys.mapStyle) private var mapStyleRaw = MapStyleChoice.standard.rawValue
    @AppStorage(AppSettingsKeys.highAccuracy) private var highAccuracy = true
    
    var body: some View {
        GeometryReader { geometry in
            let menuWidth = geometry.size.width * 0.82
            
            ZStack(alignment: .leading) {
                // PRIMARY SCREEN UNDERLAY VIEWPORT CANVAS
                ZStack(alignment: .top) {
                    Map(position: $viewportCamera) {
                        ForEach(getMapPins()) { pin in
                            Annotation("", coordinate: pin.coordinate) {
                                MemberMapMarker(pin: pin)
                                    .onTapGesture { focusOnPin(pin) }
                            }
                        }
                        
                        ForEach(trackingEngine.activeGeofences) { place in
                            Annotation("", coordinate: place.coordinate) {
                                PlaceMapMarker(place: place)
                            }
                        }
                    }
                    .mapStyle((MapStyleChoice(rawValue: mapStyleRaw) ?? .standard).style)
                    .ignoresSafeArea(edges: .all)
                    
                    // Top Bar Floating Map Controls Layer
                    HStack(alignment: .top) {
                        Button(action: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                contextualSheetPresented = false
                                showHamburgerMenu = true
                            }
                        }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .padding(12)
                                .background(Circle().fill(Color(.systemBackground)).shadow(radius: 4))
                        }
                        .padding(.leading, 16)
                        
                        Spacer()

                        VStack(spacing: 12) {
                            mapControl(icon: "location.fill", tint: .blue, action: recenterOnUser)
                            mapControl(icon: "bubble.left.and.bubble.right.fill", tint: .purple) {
                                contextualSheetPresented = false
                                showChat = true
                            }
                            sosControl
                        }
                        .padding(.trailing, 16)
                    }
                    .padding(.top, 64)
                }
                .disabled(showHamburgerMenu)
                
                if showHamburgerMenu {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showHamburgerMenu = false
                                contextualSheetPresented = true
                            }
                        }
                        .transition(.opacity)
                }
                
                // HAMBURGER SETTINGS DRAWER OVERLAY
                SettingsDrawerView(
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showHamburgerMenu = false
                            contextualSheetPresented = true
                        }
                    },
                    onSignOut: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showHamburgerMenu = false
                            authContext.performSecureLogout()
                        }
                    }
                )
                .frame(width: menuWidth)
                .ignoresSafeArea(edges: .vertical)
                .offset(x: showHamburgerMenu ? 0 : -menuWidth)
            }
            .sheet(isPresented: $contextualSheetPresented) {
                TelemetryDashboardDrawer()
                    .presentationDetents([.height(150), .medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationCornerRadius(30)
                    .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showUserDetailSheet, onDismiss: { contextualSheetPresented = true }) {
                if let profile = authContext.currentUserProfile {
                    OperatorDetailView(profile: profile, isCurrentUser: true)
                } else {
                    Text("No operator data available")
                }
            }
            .sheet(item: $selectedRemoteMember, onDismiss: { contextualSheetPresented = true }) { member in
                OperatorDetailView(profile: member, isCurrentUser: false)
            }
            .sheet(isPresented: $showChat, onDismiss: { contextualSheetPresented = true }) {
                ChatView(currentUserId: circleSync.currentUsername ?? "")
            }
            .alert("Send SOS to your circle?", isPresented: $showSOSConfirm) {
                Button("Send SOS", role: .destructive) { circleSync.setSOS(true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your circle will be alerted with your live location until you cancel.")
            }
            .task {
                trackingEngine.applyAccuracyPreference(highAccuracy: highAccuracy)
                trackingEngine.beginAmbientLocationUpdates()
            }
        }
    }

    // MARK: - Map controls

    private func mapControl(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(.systemBackground)).shadow(radius: 4))
        }
    }

    @ViewBuilder
    private var sosControl: some View {
        Button {
            if circleSync.isBroadcastingSOS {
                circleSync.setSOS(false)
            } else {
                showSOSConfirm = true
            }
        } label: {
            Image(systemName: circleSync.isBroadcastingSOS ? "exclamationmark.triangle.fill" : "sos.circle.fill")
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.red).shadow(radius: 4))
        }
    }

    private func recenterOnUser() {
        let target = trackingEngine.liveLocation ?? authContext.currentUserProfile?.coordinate
        guard let target else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            viewportCamera = .region(MKCoordinateRegion(
                center: target,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }

    private func getMapPins() -> [LocalMapMarkerIdentifier] {
        var pins: [LocalMapMarkerIdentifier] = []
        let myUsername = circleSync.currentUsername

        // Current operator rendered from this device's live GPS fix.
        if let profile = authContext.currentUserProfile {
            let dynamicCoordinate = trackingEngine.liveLocation ?? profile.coordinate
            pins.append(
                LocalMapMarkerIdentifier(
                    id: profile.id,
                    name: profile.name,
                    coordinate: dynamicCoordinate,
                    isCurrentUser: true,
                    isCharging: profile.isCharging,
                    batteryPercentage: profile.batteryPercentage,
                    avatarBase64: profile.avatarBase64
                )
            )
        }

        // Every other circle member sourced live from the shared database.
        for member in circleSync.members {
            if let myUsername, member.username == myUsername { continue }
            pins.append(
                LocalMapMarkerIdentifier(
                    id: member.id,
                    name: member.name,
                    coordinate: member.coordinate,
                    isCurrentUser: false,
                    isCharging: member.isCharging,
                    batteryPercentage: member.batteryPercentage,
                    avatarBase64: member.avatarBase64
                )
            )
        }

        return pins
    }

    private func focusOnPin(_ pin: LocalMapMarkerIdentifier) {
        withAnimation(.easeInOut(duration: 0.4)) {
            viewportCamera = .region(MKCoordinateRegion(
                center: pin.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
        contextualSheetPresented = false
        if pin.isCurrentUser {
            showUserDetailSheet = true
        } else if let member = circleSync.members.first(where: { $0.id == pin.id }) {
            selectedRemoteMember = member
        }
    }
}

// MARK: - Map markers

private struct MemberMapMarker: View {
    let pin: LocalMapMarkerIdentifier

    var body: some View {
        VStack(spacing: 2) {
            if pin.isCurrentUser {
                currentUserMarker
            } else {
                MemberAvatar(name: pin.name, isCharging: pin.isCharging, size: 46, image: AvatarCache.image(forBase64: pin.avatarBase64))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
            }

            HStack(spacing: 4) {
                Text(pin.name)
                batteryTag
            }
            .font(.caption2)
            .bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 1))
        }
    }

    /// Exact battery percentage shown on the pin, with a charging bolt when plugged
    /// in and a glyph that reflects the actual charge level.
    private var batteryTag: some View {
        HStack(spacing: 2) {
            Image(systemName: batterySymbol)
                .font(.system(size: 8))
            Text("\(pin.batteryPercentage)%")
        }
        .foregroundColor(pin.isCharging ? .green : (pin.batteryPercentage < 20 ? .red : .secondary))
    }

    private var batterySymbol: String {
        if pin.isCharging { return "battery.100.bolt" }
        switch pin.batteryPercentage {
        case ..<15: return "battery.25"
        case ..<50: return "battery.50"
        case ..<80: return "battery.75"
        default: return "battery.100"
        }
    }

    // The current user's own pin shows their profile picture too, with a blue
    // accuracy halo + ring so "you" stays distinguishable from other members.
    private var currentUserMarker: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.18)).frame(width: 58, height: 58)
            MemberAvatar(name: pin.name, isCharging: pin.isCharging, size: 46, image: AvatarCache.image(forBase64: pin.avatarBase64))
                .overlay(Circle().stroke(Color.blue, lineWidth: 3))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
        }
        .frame(width: 58, height: 58)
    }
}

private struct PlaceMapMarker: View {
    let place: GeofenceZone

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.2)).frame(width: 38, height: 38)
                Circle().fill(Color.white).frame(width: 30, height: 30).shadow(radius: 2)
                Text(place.emojiIcon.isEmpty ? "📍" : place.emojiIcon).font(.system(size: 18))
            }
            Text(place.name.prefix(12) + (place.name.count > 12 ? "..." : ""))
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground)).shadow(radius: 1))
        }
    }
}
