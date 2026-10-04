import Foundation
import UserNotifications
import VocabularyCore
import VocabularyData

/// Starts a plan when the learner taps its reminder, and shows reminders that arrive while the app
/// is open (SPEC C10).
final class ReminderDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let open: @MainActor @Sendable (URL) -> Void

    init(open: @escaping @MainActor @Sendable (URL) -> Void) {
        self.open = open
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Only a plan's link: a reminder never opens a file or anything else (security review).
        guard let link = response.notification.request.content.userInfo[PlanNotificationScheduler.urlKey] as? String,
              let url = URL(string: link), DeepLink(url: url) != nil
        else { return }
        await open(url)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
