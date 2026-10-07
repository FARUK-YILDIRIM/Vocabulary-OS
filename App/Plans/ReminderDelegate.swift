import Foundation
import UserNotifications
import VocabularyCore
import VocabularyData

/// Starts a plan when the learner taps its reminder, and shows reminders that arrive while the app
/// is open (SPEC C10).
///
/// The methods run on the main actor, so the system's completion handler is called on the main
/// thread when they return. For a reminder tapped while the app was in the background, UIKit then
/// updates the app's snapshot, and off the main thread that stopped the app.
final class ReminderDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let open: @MainActor @Sendable (URL) -> Void

    init(open: @escaping @MainActor @Sendable (URL) -> Void) {
        self.open = open
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Only a plan's link: a reminder never opens a file or anything else (security review).
        guard let link = response.notification.request.content.userInfo[PlanNotificationScheduler.urlKey] as? String,
              let url = URL(string: link), DeepLink(url: url) != nil
        else { return }
        open(url)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
