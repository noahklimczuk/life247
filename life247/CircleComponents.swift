//
//  CircleComponents.swift
//  life247
//
//  Reusable Life360-style presentation pieces for circle members: a deterministic
//  per-member colour, a circular avatar (with charging badge), and a rich member
//  row that resolves the member's current address and shows live status.
//

import SwiftUI
import CoreLocation
import MapKit
import UIKit

// MARK: - Palette

enum MemberPalette {
    private static let palette: [Color] = [
        .blue, .purple, .pink, .orange, .green, .teal, .indigo, Color(red: 0.9, green: 0.3, blue: 0.4)
    ]

    /// Stable colour for a member, derived from their name so it never changes
    /// between launches.
    static func color(for name: String) -> Color {
        let key = name.lowercased()
        guard !key.isEmpty else { return .blue }
        let sum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    static func initials(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        if parts.count >= 2 {
            return parts.map { String($0.prefix(1)) }.joined().uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Avatar image cache

/// Decodes base64 profile pictures once and caches the resulting images so the
/// 5-second roster polls don't re-decode the same avatar on every refresh.
enum AvatarCache {
    private static let cache = NSCache<NSString, UIImage>()

    /// Returns the decoded image for a base64 JPEG string, caching by the string.
    static func image(forBase64 base64: String?) -> UIImage? {
        guard let base64, !base64.isEmpty else { return nil }
        let key = base64 as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = Data(base64Encoded: base64), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Downscales an image to a small square thumbnail and encodes it as base64
    /// JPEG, small enough to ride along in the Realtime Database member node.
    static func encode(_ image: UIImage, maxDimension: CGFloat = 96, quality: CGFloat = 0.5) -> String? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }

        return resized.jpegData(compressionQuality: quality)?.base64EncodedString()
    }
}

// MARK: - Avatar

struct MemberAvatar: View {
    let name: String
    var isCharging: Bool = false
    var size: CGFloat = 48
    var image: UIImage? = nil

    var body: some View {
        let color = MemberPalette.color(for: name)
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(color, lineWidth: max(2, size * 0.06)))
                } else {
                    Circle()
                        .fill(color.opacity(0.18))
                        .overlay(Circle().stroke(color, lineWidth: max(2, size * 0.06)))
                        .frame(width: size, height: size)
                        .overlay(
                            Text(MemberPalette.initials(for: name))
                                .font(.system(size: size * 0.36, weight: .bold))
                                .foregroundColor(color)
                        )
                }
            }

            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(size * 0.10)
                    .background(Circle().fill(Color.green))
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: max(1, size * 0.04)))
                    .offset(x: size * 0.06, y: size * 0.06)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Member Row

/// A Life360-style member row: avatar, name, reverse-geocoded address, "time ago",
/// battery (with charging) and a movement badge.
struct CircleMemberRow: View {
    let member: UserState
    let isCurrentUser: Bool
    let isTracking: Bool

    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine

    @State private var address = "Locating…"
    @State private var lastGeocodedKey = ""

    private var coordinate: CLLocationCoordinate2D {
        if isCurrentUser, let live = trackingEngine.liveLocation { return live }
        return member.coordinate
    }

    private var coordKey: String {
        String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
    }

    private var charging: Bool {
        if isCurrentUser {
            let s = UIDevice.current.batteryState
            return s == .charging || s == .full
        }
        return member.isCharging
    }

    private var speedText: String { UnitFormatter.speedString(metersPerSecond: member.currentSpeed) }

    /// The saved place the member is currently inside, if any.
    private var presencePlace: GeofenceZone? {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return trackingEngine.activeGeofences.first { zone in
            here.distance(from: CLLocation(latitude: zone.latitude, longitude: zone.longitude)) <= zone.radius
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            MemberAvatar(name: member.name, isCharging: charging, size: 52, image: AvatarCache.image(forBase64: member.avatarBase64))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.headline)
                    if isCurrentUser {
                        Text("You")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(MemberPalette.color(for: member.name).opacity(0.16)))
                            .foregroundColor(MemberPalette.color(for: member.name))
                    }
                    Spacer()
                    batteryBadge
                }

                if let place = presencePlace {
                    HStack(spacing: 5) {
                        Text(place.emojiIcon.isEmpty ? "📍" : place.emojiIcon)
                            .font(.caption)
                        Text("at \(place.name)")
                            .font(.subheadline).bold()
                            .foregroundColor(.purple)
                            .lineLimit(1)
                    }
                } else {
                    Text(address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(timeAgo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    movementBadge
                    if member.isSOS {
                        badge(text: "SOS", systemImage: "exclamationmark.triangle.fill", color: .red)
                    }
                    Spacer()
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 30))
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.trailing, 12)
        }
        .contentShape(Rectangle())
        .onAppear(perform: geocodeIfNeeded)
        .onChange(of: coordKey) { _, _ in geocodeIfNeeded() }
    }

    // MARK: Subviews

    private var batteryBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: batterySymbol)
                .foregroundColor(batteryColor)
            Text("\(member.batteryPercentage)%")
                .foregroundColor(.secondary)
        }
        .font(.caption.bold())
    }

    @ViewBuilder
    private var movementBadge: some View {
        if isCurrentUser && isTracking {
            badge(text: "Live", systemImage: "dot.radiowaves.left.and.right", color: .green)
        } else {
            switch member.activity {
            case .driving:
                badge(text: "Driving \(speedText)", systemImage: "car.fill", color: .blue)
            case .walking:
                badge(text: "Walking", systemImage: "figure.walk", color: .teal)
            case .stationary:
                EmptyView()
            }
        }
    }

    private func badge(text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption2.bold())
        .foregroundColor(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: Derived values

    private var batterySymbol: String {
        if charging { return "battery.100.bolt" }
        switch member.batteryPercentage {
        case ..<15: return "battery.25"
        case ..<50: return "battery.50"
        case ..<80: return "battery.75"
        default: return "battery.100"
        }
    }

    private var batteryColor: Color {
        if charging { return .green }
        return member.batteryPercentage < 20 ? .red : .secondary
    }

    private var timeAgo: String {
        if isCurrentUser { return "Now" }
        let seconds = Date().timeIntervalSince(member.lastUpdated)
        switch seconds {
        case ..<60: return "Now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86400))d ago"
        }
    }

    // MARK: Geocoding

    private func geocodeIfNeeded() {
        let key = coordKey
        guard key != lastGeocodedKey else { return }
        lastGeocodedKey = key

        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: loc) else {
            address = "Address unavailable"
            return
        }
        Task {
            let resolved = try? await request.mapItems.first?.address?.compactAddress
            await MainActor.run {
                self.address = resolved ?? "Address unavailable"
            }
        }
    }
}

private extension MKAddress {
    /// A compact "street, city" style address derived from the full address.
    var compactAddress: String {
        let full = fullAddress
        guard !full.isEmpty else { return "Address unavailable" }
        let parts = full.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 2 { return parts.prefix(2).joined(separator: ", ") }
        return full
    }
}
