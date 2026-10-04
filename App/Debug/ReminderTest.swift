#if DEBUG
import Foundation
import UserNotifications
import VocabularyData

/// Sends the first plan's reminder a few seconds after launch (`-vos-remind-in 3`), so UI tests can
/// tap a real notification without waiting for its time (Debug builds only).
enum ReminderTest {
    static func sendIfRequested(app: AppModel, options: LaunchOptions = LaunchOptions()) async {
        guard let seconds = options.remindInSeconds, let plan = try? app.activePlans().first else { return }
        guard await app.requestReminderPermission() else { return }
        let content = PlanNotificationScheduler.content(for: plan, text: PlanText.reminder(for: plan))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "reminder-test", content: content, trigger: trigger))
    }
}
#endif
