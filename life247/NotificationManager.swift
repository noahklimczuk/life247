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

    /// Identifier for the repeating SOS alert so it can be cancelled when cleared.
    private let sosRepeatIdentifier = "life247.sos.persistent"

    private override init() { super.init() }

    /// Requests alert/sound/badge authorization and installs the foreground
    /// presenter so notifications also appear while the app is open. Also asks for
    /// the Critical Alerts permission so SOS can break through silent/Focus modes
    /// (only effective once Apple grants the matching entitlement).
    func bootstrap() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { _, _ in }
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

    /// Posts a high-priority SOS alert that forces a loud sound even when the
    /// ringer is off (with the Critical Alerts entitlement) and keeps re-firing
    /// every 30s until `clearSOS()` is called, so it can't be missed. The repeat
    /// is a local trigger, so it persists even if the app is later killed.
    func postSOS(title: String, body: String) {
        let center = UNUserNotificationCenter.current()

        // Cancel any earlier SOS repeat before starting a fresh one.
        center.removePendingNotificationRequests(withIdentifiers: [sosRepeatIdentifier])

        // Immediate alert.
        center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                         content: sosContent(title: title, body: body),
                                         trigger: nil))

        // Persistent re-alert until the SOS is resolved.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: true)
        center.add(UNNotificationRequest(identifier: sosRepeatIdentifier,
                                         content: sosContent(title: title, body: body),
                                         trigger: trigger))
    }

    /// Cancels the repeating SOS alert once the sender clears their SOS.
    func clearSOS() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [sosRepeatIdentifier])
    }

    private func sosContent(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .critical
        content.sound = .defaultCriticalSound(withAudioVolume: 1.0)
        return content
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
