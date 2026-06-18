//
//  MainApplicationTelemetryWorkspace.swift
//  life247
//
//  Created by Noah Klimczuk on 2026-06-15.
//

import SwiftUI
import MapKit

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
                // ==========================================
                // PRIMARY SCREEN UNDERLAY VIEWPORT CANVAS
                // ==========================================
                ZStack(alignment: .top) {
                    Map(position: $viewportCamera) {
                        ForEach(getMapPins()) { pin in
                            Annotation(pin.name, coordinate: pin.coordinate) {
                                VStack(spacing: 2) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Circle()
                                            .fill(pin.isCurrentUser ? Color.blue : Color.purple)
                                            .frame(width: 44, height: 44)
                                        
                                        Text(String(pin.name.prefix(2)).uppercased())
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 44, height: 44, alignment: .center)
                                        
                                        if authContext.currentUserProfile != nil && pin.isCurrentUser {
                                            ZStack {
                                                Circle().fill(Color.black.opacity(0.8)).frame(width: 18, height: 18)
                                                Text("🔋")
                                                    .font(.system(size: 10))
                                            }
                                            .offset(x: 4, y: 4)
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
                                        Text("📍").font(.system(size: 18))
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
                        // --- HAMBURGER MENU TOGGLE BUTTON ---
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
                            Button(action: {
                                if let live = trackingEngine.liveLocation {
                                    withAnimation { viewportCamera = .camera(MapCamera(centerCoordinate: live, distance: 1000)) }
                                }
                            }) {
                                Image(systemName: "location.north.line.fill")
                                    .font(.title3)
                                    .padding(12)
                                    .background(Circle().fill(Color(.systemBackground)).shadow(radius: 4))
                            }
                        }
                        .padding(.trailing, 16)
                    }
                    .padding(.top, 64)
                    
                    // Inside Zone Active HUD Capsule
                    VStack {
                        if trackingEngine.currentActiveZoneID != nil {
                            HStack {
                                Image(systemName: "clock.badge.checkmark.fill").foregroundColor(.green)
                                Text(trackingEngine.insideZoneTimerText).font(.system(.subheadline, design: .monospaced)).bold()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 3))
                            .padding(.top, 12)
                        }
                    }
                }
                .disabled(showHamburgerMenu) // Prevent map interactions while menu is open
                
                // ==========================================
                // DARK REAR WALL DISMISSAL OVERLAY
                // ==========================================
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
                
                // ==========================================
                // HAMBURGER SETTINGS DRAWER OVERLAY
                // ==========================================
                VStack(spacing: 0) {
                    // Drawer Header
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
                    .background(Color(red: 0.15, green: 0.05, blue: 0.25)) // Purple Theme Core Header
                    
                    // Settings Body Components Group Form Container
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
                            
                            HStack {
                                Text("Status:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(trackingEngine.currentActiveZoneID != nil ? "Stationary Inside Zone" : "In Transit / Active")
                                        .font(.subheadline)
                                        .bold()
                            }
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
                                Spacer()
                                Text("Dynamic Optimization Active").foregroundColor(.secondary).font(.footnote)
                            }
                            HStack {
                                Text("Sensor Diagnostics:")
                                Spacer()
                                Text(trackingEngine.liveLocation != nil ? "Operational" : "Synchronizing...").foregroundColor(trackingEngine.liveLocation != nil ? .green : .orange).bold()
                            }
                        }
                        
                        Section {
                            Button(role: .destructive, action: {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showHamburgerMenu = false
                                    // Trigger auth state reset -> forces view switch to login screen instantly
                                    authContext.performSecureLogout()
                                }
                            }) {
                                sigoutButtonLabel
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
        }
        .onAppear {
            trackingEngine.synchronizeTrackingState(isActive: true)
            trackingEngine.startLiveBatteryMonitoring(authContext: authContext)
        }
        .sheet(isPresented: $contextualSheetPresented) {
            TelemetryDashboardDrawer(registeredZones: $dynamicGeofenceZones)
                .presentationDetents([.height(88), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationCornerRadius(30)
                .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showUserDetailSheet, onDismiss: { contextualSheetPresented = true }) {
            NavigationStack {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(String(authContext.currentUserProfile?.name.prefix(2) ?? "OP").uppercased())
                                    .font(.headline)
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authContext.currentUserProfile?.name ?? "Telemetry Operator")
                                .font(.title3)
                                .bold()
                                .foregroundColor(.white)
                            Text("System Telemetry Node • Connected")
                                .font(.caption)
                                .foregroundColor(.blue.opacity(0.8))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .padding(.top, 10)
                    .background(Color(red: 0.05, green: 0.08, blue: 0.14))
                    
                    List {
                        Section("Current Location Telemetry") {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "mappin.circle.fill").foregroundColor(.red)
                                    Text("Geographic Coordinates").font(.caption).foregroundColor(.secondary)
                                }
                                if let coordinate = trackingEngine.liveLocation ?? authContext.currentUserProfile?.coordinate {
                                    Text(String(format: "Lat: %.5f, Lon: %.5f", coordinate.latitude, coordinate.longitude))
                                        .font(.system(.subheadline, design: .monospaced))
                                        .bold()
                                } else {
                                    Text("Resolving satellite positioning...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Section("Hardware Diagnostics") {
                            HStack {
                                Label("Battery Level", systemImage: "battery.100")
                                Spacer()
                                let batteryPct = authContext.currentUserProfile?.batteryPercentage ?? 100
                                Text("\(batteryPct)%")
                                    .font(.body).bold()
                                    .foregroundColor(batteryPct > 20 ? .green : .red)
                            }
                        }
                        
                        Section("Active Workspace Infrastructure") {
                            if dynamicGeofenceZones.isEmpty {
                                Text("No registered operational zones discovered.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(dynamicGeofenceZones) { zone in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(zone.name)
                                            .font(.subheadline)
                                            .bold()
                                        Text(String(format: "Radius Boundary: %.0fm • Center Pin Verified", zone.radius))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Operator Briefing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showUserDetailSheet = false }.foregroundColor(.white)
                    }
                }
                .toolbarBackground(Color(red: 0.05, green: 0.08, blue: 0.14), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(25)
        }
    }
    
    // Extracted subview clean-up to improve type check processing times
    private var sigoutButtonLabel: some View {
        HStack {
            Spacer()
            Image(systemName: "power")
            Text("Log Out").bold()
            Spacer()
        }
        .foregroundColor(.white)
    }
    
    private func getMapPins() -> [MapPinNode] {
        var pins: [MapPinNode] = []
        if let current = authContext.currentUserProfile {
            let latestCoords = trackingEngine.liveLocation ?? current.coordinate
            pins.append(MapPinNode(name: current.name, coordinate: latestCoords, isCurrentUser: true))
        }
        return pins
    }
}
