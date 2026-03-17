import AppKit
import Foundation
import UserNotifications

@MainActor
final class NeoCodeNotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func postIfApplicationInactive(identifier: String, title: String, body: String) async {
        guard !NSApplication.shared.isActive else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }
}
