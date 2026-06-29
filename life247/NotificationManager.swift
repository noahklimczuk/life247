//
//  NotificationManager.swift
//  life247
//
//  Centralized local-notification helper. Because the app is SDK-free with no
//  server, cross-device alerts are delivered as local notifications fired by the
//  receiving device while the app is running (foreground or backgrounded with
//  location updates) — there is no APNs push path.
//

import Foundation
import UserNotifications

enum NotificationCategory: String {
    case place
    case battery
    case sos
    case chat
    case checkIn
    case trip
}

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() { super.init() }

    /// Requests alert/sound/badge authorization and installs the foreground
    /// presenter so notifications also appear while the app is open.
    func bootstrap() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Posts a local notification immediately. `category` gates whether it should
    /// fire based on the user's notification preferences (SOS always fires).
    func post(title: String, body: String, category: NotificationCategory) {
        guard shouldDeliver(category) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func shouldDeliver(_ category: NotificationCategory) -> Bool {
        let defaults = UserDefaults.standard
        switch category {
        case .place, .checkIn: return defaults.bool(forKey: AppSettingsKeys.placeAlerts)
        case .battery: return defaults.bool(forKey: AppSettingsKeys.lowBatteryAlerts)
        case .chat: return defaults.bool(forKey: AppSettingsKeys.chatAlerts)
        case .trip: return defaults.bool(forKey: AppSettingsKeys.autoRouteRecording)
        case .sos: return true
        }
    }

    // Show banners even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
