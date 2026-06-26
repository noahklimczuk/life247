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
}

struct MainApplicationTelemetryWorkspace: View {
    @EnvironmentObject var authContext: SessionAuthContext
    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine
    
    @State private var viewportCamera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var contextualSheetPresented = true
    @State private var dynamicGeofenceZones: [GeofenceZone] = []
    
    // Controls the visible open state of the side drawer panel
    @State private var showHamburgerMenu = false
    @State private var showUserDetailSheet = false
    
    // Local state toggles to drive your telemetry settings options
    @State private var highAccuracyTracking = true
    @State private var geofenceNotifications = true
    @State private var routeRecordingAutomation = true
    @State private var shareLocationWithCircle = true
    
    var body: some View {
        GeometryReader { geometry in
            let menuWidth = geometry.size.width * 0.82
            
            ZStack(alignment: .leading) {
                // PRIMARY SCREEN UNDERLAY VIEWPORT CANVAS
                ZStack(alignment: .top) {
                    Map(position: $viewportCamera) {
                        ForEach(getMapPins()) { pin in
                            Annotation(pin.name, coordinate: pin.coordinate) {
                                VStack(spacing: 2) {
                                    if pin.isCurrentUser {
                                        // Find My-style blue location dot: soft accuracy
                                        // halo, white ring, solid blue core.
                                        ZStack(alignment: .bottomTrailing) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.blue.opacity(0.18))
                                                    .frame(width: 58, height: 58)
                                                Circle()
                                                    .fill(Color.white)
                                                    .frame(width: 28, height: 28)
                                                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                                                Circle()
                                                    .fill(Color.blue)
                                                    .frame(width: 22, height: 22)
                                            }
                                            .frame(width: 58, height: 58)

                                            if authContext.currentUserProfile != nil {
                                                ZStack {
                                                    Circle().fill(Color.black.opacity(0.8)).frame(width: 18, height: 18)
                                                    Text("🔋")
                                                        .font(.system(size: 10))
                                                }
                                                .offset(x: 2, y: 2)
                                            }
                                        }
                                    } else {
                                        ZStack {
                                            Circle()
                                                .fill(Color.purple)
                                                .frame(width: 44, height: 44)

                                            Text(String(pin.name.prefix(2)).uppercased())
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                                .frame(width: 44, height: 44, alignment: .center)
                                        }
                                    }
                                    
                                    Text(pin.name)
                                        .font(.caption2)
                                        .bold()
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 1))
                                }
                                .onTapGesture {
                                    if pin.isCurrentUser {
                                        contextualSheetPresented = false
                                        showUserDetailSheet = true
                                    }
                                }
                            }
                        }
                        
                        ForEach(dynamicGeofenceZones) { place in
                            Annotation(place.name, coordinate: place.coordinate) {
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
                    }
                    .ignoresSafeArea(edges: .all)
                    
                    // Top Bar Floating Map Controls Layer
                    HStack {
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
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("System Settings")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showHamburgerMenu = false
                                    contextualSheetPresented = true
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(8)
                                    .background(Circle().fill(Color.white.opacity(0.15)))
                            }
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .background(Color(red: 0.15, green: 0.05, blue: 0.25))
                    
                    Form {
                        Section("Profile & Status") {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundColor(.gray)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Operator")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(authContext.currentUserProfile?.name ?? "Unknown Node")
                                        .font(.body)
                                        .bold()
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Section("Telemetry Preferences") {
                            Toggle("High-Accuracy Tracking", isOn: $highAccuracyTracking)
                            Toggle("Geofence Notifications", isOn: $geofenceNotifications)
                            Toggle("Route Recording Auto", isOn: $routeRecordingAutomation)
                            Toggle("Share Location", isOn: $shareLocationWithCircle)
                        }
                        .tint(.purple)
                        
                        Section("Hardware Status") {
                            HStack {
                                Text("Map Cache:")
                                    .font(.body)
                                Spacer()
                                Text("Dynamic Optimization Active").foregroundColor(.secondary).font(.footnote)
                            }
                        }
                        
                        Section {
                            Button(role: .destructive, action: {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showHamburgerMenu = false
                                    authContext.performSecureLogout()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.forward")
                                    Text("Sign Out Securely")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red)
                            )
                        } footer: {
                            VStack(alignment: .center, spacing: 4) {
                                Text("Revokes access & clears session data.")
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                
                                Text("life247 Telemetry Core API v1.2")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .frame(width: menuWidth)
                .background(Color(.systemGroupedBackground))
                .ignoresSafeArea(edges: .vertical)
                .offset(x: showHamburgerMenu ? 0 : -menuWidth)
            }
            .sheet(isPresented: $contextualSheetPresented) {
                TelemetryDashboardDrawer(registeredZones: $dynamicGeofenceZones)
                    .presentationDetents([.height(88), .medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationCornerRadius(30)
                    .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showUserDetailSheet, onDismiss: { contextualSheetPresented = true }) {
                if let profile = authContext.currentUserProfile {
                    OperatorDetailView(profile: profile)
                } else {
                    Text("No operator data available")
                }
            }
            // FIXED: Uses standard array count tracking expression which resolves the Hashable non-conformance compiler failure
            .onChange(of: dynamicGeofenceZones.count) { oldCount, newCount in
                for zone in dynamicGeofenceZones {
                    if !trackingEngine.activeGeofences.contains(where: { $0.id == zone.id }) {
                        trackingEngine.registerGeofenceHardwareBoundary(for: zone)
                    }
                }
            }
            .task {
                self.dynamicGeofenceZones = trackingEngine.activeGeofences
            }
        }
    }
    
    private func getMapPins() -> [LocalMapMarkerIdentifier] {
        guard let profile = authContext.currentUserProfile else { return [] }
        
        let dynamicCoordinate = CLLocationCoordinate2D(
            latitude: profile.latitude,
            longitude: profile.longitude
        )
        
        return [
            LocalMapMarkerIdentifier(
                id: profile.id,
                name: profile.name,
                coordinate: dynamicCoordinate,
                isCurrentUser: true
            )
        ]
    }
}
