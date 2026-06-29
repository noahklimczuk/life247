//
//  SettingsDrawerView.swift
//  life247
//
//  Polished settings panel shown in the side drawer.
//

import SwiftUI
import PhotosUI
import UIKit

struct SettingsDrawerView: View {
    @EnvironmentObject var authContext: SessionAuthContext
    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine

    let onClose: () -> Void
    let onSignOut: () -> Void

    @AppStorage(AppSettingsKeys.shareLocation) private var shareLocation = true
    @AppStorage(AppSettingsKeys.highAccuracy) private var highAccuracy = true
    @AppStorage(AppSettingsKeys.placeAlerts) private var placeAlerts = true
    @AppStorage(AppSettingsKeys.lowBatteryAlerts) private var lowBatteryAlerts = true
    @AppStorage(AppSettingsKeys.chatAlerts) private var chatAlerts = true
    @AppStorage(AppSettingsKeys.autoRouteRecording) private var autoRouteRecording = true
    @AppStorage(AppSettingsKeys.useMiles) private var useMiles = false
    @AppStorage(AppSettingsKeys.mapStyle) private var mapStyleRaw = MapStyleChoice.standard.rawValue
    @AppStorage(AppSettingsKeys.relayPushEnabled) private var relayPushEnabled = false
    @AppStorage(AppSettingsKeys.relayTopic) private var relayTopic = ""

    @State private var showSignOutConfirm = false
    @State private var clearedHistory = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var nameDraft = ""

    private var displayName: String { authContext.currentUserProfile?.name ?? "Operator" }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                profileSection
                locationSection
                notificationsSection
                relaySection
                mapUnitsSection
                dataSection
                accountSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
        }
        .padding(.top, 60)
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.07, blue: 0.36), Color(red: 0.32, green: 0.12, blue: 0.52)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        MemberAvatar(name: displayName, size: 56, image: AvatarCache.image(forBase64: authContext.currentUserProfile?.avatarBase64))
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color.purple))
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Display name", text: $nameDraft)
                        .font(.title3.bold())
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(commitName)
                    HStack(spacing: 5) {
                        Circle().fill(shareLocation ? Color.green : Color.orange).frame(width: 8, height: 8)
                        Text(shareLocation ? "Sharing location" : "Location paused")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)

            if authContext.currentUserProfile?.avatarBase64 != nil {
                Button(role: .destructive) {
                    selectedPhoto = nil
                    authContext.updateAvatar(nil)
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        } header: {
            Text("Profile")
        } footer: {
            Text("Your name and photo are shared with your circle.")
        }
        .onAppear { if nameDraft.isEmpty { nameDraft = displayName } }
        .onDisappear(perform: commitName)
        .onChange(of: selectedPhoto) { _, newItem in loadPhoto(newItem) }
    }

    /// Saves the edited display name (when changed) to the profile and circle.
    private func commitName() {
        guard authContext.currentUserProfile != nil else { return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != displayName else { return }
        authContext.updateDisplayName(trimmed)
    }

    /// Loads the picked photo and stores it as the operator's profile picture.
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run { authContext.updateAvatar(image) }
            }
        }
    }

    private var locationSection: some View {
        Section {
            Toggle("Share My Location", isOn: $shareLocation)
            Toggle("High-Accuracy Tracking", isOn: $highAccuracy)
                .onChange(of: highAccuracy) { _, newValue in
                    trackingEngine.applyAccuracyPreference(highAccuracy: newValue)
                }
        } header: {
            Text("Location Sharing")
        } footer: {
            Text("Turn off sharing to go invisible to your circle. High accuracy uses more battery.")
        }
        .tint(.purple)
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Place Arrival & Departure", isOn: $placeAlerts)
            Toggle("Low Battery Alerts", isOn: $lowBatteryAlerts)
            Toggle("Chat Messages", isOn: $chatAlerts)
        }
        .tint(.purple)
    }

    private var relaySection: some View {
        Section {
            Toggle("Off-App Push", isOn: $relayPushEnabled)
            HStack {
                TextField("shared topic", text: $relayTopic)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                if relayTopic.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Generate") { relayTopic = Self.suggestedTopic() }
                        .font(.caption.bold())
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Off-App Push (ntfy)")
        } footer: {
            Text("Get alerts even when life247 is force-quit. Install the free ntfy app on both phones and subscribe to this exact topic. Keep it secret — anyone who knows it can read your alerts.")
        }
        .tint(.purple)
    }

    private static func suggestedTopic() -> String {
        "life247-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    }

    private var mapUnitsSection: some View {
        Section("Map & Units") {
            Picker("Map Style", selection: $mapStyleRaw) {
                ForEach(MapStyleChoice.allCases) { choice in
                    Label(choice.label, systemImage: choice.symbol).tag(choice.rawValue)
                }
            }

            Picker("Units", selection: $useMiles) {
                Text("Kilometers").tag(false)
                Text("Miles").tag(true)
            }
            .pickerStyle(.segmented)

            Toggle("Auto Trip Recording", isOn: $autoRouteRecording)
                .tint(.purple)
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                trackingEngine.clearTripHistory()
                withAnimation { clearedHistory = true }
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text(clearedHistory ? "Trip History Cleared" : "Clear Trip History")
                    Spacer()
                }
                .foregroundColor(clearedHistory ? .secondary : .red)
            }
            .disabled(clearedHistory || trackingEngine.recordedDrivesHistory.isEmpty)
        } header: {
            Text("Data & Privacy")
        } footer: {
            Text("Removes locally stored driving trips from this device.")
        }
    }

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.forward")
                    Text("Sign Out")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(Color.red))
        }
        .confirmationDialog("Sign out of life247?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive, action: onSignOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears your session on this device.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            HStack {
                Text("Live Sync")
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Connected").foregroundColor(.secondary)
                }
            }
            HStack {
                Text("Circle")
                Spacer()
                Text("Just the two of us ❤️").foregroundColor(.secondary)
            }
        }
    }
}
