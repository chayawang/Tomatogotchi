import Foundation
import UserNotifications

/// Explicit opt-in development probe. No permission request, pet mutation or
/// normal reminder cleanup; only this probe's unique notification is removed.
@MainActor
enum NativeNotificationProbe {
    static func run(directory: URL) async {
        let center = UNUserNotificationCenter.current()
        let id = "work.shiroi.tomatogotchi.qa.probe." + UUID().uuidString
        let output = directory.appendingPathComponent("notification-probe.json")
        var report: [String: Any] = ["requestID": id, "delivered": false,
                                     "visualBannerVerified": false, "clickVerified": false]
        defer {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.removeDeliveredNotifications(withIdentifiers: [id])
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output, options: .atomic)
            }
        }
        let settings = await center.notificationSettings()
        report["authorizationStatus"] = settings.authorizationStatus.rawValue
        switch settings.authorizationStatus {
        case .notDetermined: report["permission"] = "notDetermined"
        case .denied: report["permission"] = "denied"
        case .authorized: report["permission"] = "authorized"
        case .provisional: report["permission"] = "provisional"
        default: report["permission"] = "other"
        }
        report["alertSetting"] = settings.alertSetting.rawValue
        report["soundSetting"] = settings.soundSetting.rawValue
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            report["outcome"] = "blocked-existing-permission"
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Tomatogotchi 驗證提醒"
        content.body = "這是一則系統投遞測試通知，可直接忽略。"
        do {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            let pending = await center.pendingNotificationRequests()
            report["pendingObserved"] = pending.contains { $0.identifier == id }
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(500))
                let delivered = await center.deliveredNotifications()
                if delivered.contains(where: { $0.request.identifier == id }) {
                    report["delivered"] = true
                    report["outcome"] = "delivered"
                    return
                }
            }
            report["outcome"] = "delivery-not-observed"
        } catch {
            report["outcome"] = "error"
            report["error"] = error.localizedDescription
        }
    }
}
