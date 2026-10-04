#if os(macOS)
import AppKit
#endif
import SwiftData
import SwiftUI
import UserNotifications

@main
struct VocabularyOSApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let reminderDelegate: ReminderDelegate

    init() {
        let model = AppModel.live()
        _model = State(initialValue: model)
        // A reminder can be what launches the app, so its delegate is set before launch finishes.
        let reminderDelegate = ReminderDelegate { url in model.open(url) }
        UNUserNotificationCenter.current().delegate = reminderDelegate
        self.reminderDelegate = reminderDelegate
        #if os(macOS)
        // Service requests arrive outside SwiftUI. AppKit is running by the time this task runs, and
        // requests can only come in once the provider is set.
        let services = ServicesProvider(app: model)
        Task {
            NSApplication.shared.servicesProvider = services
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
                .onOpenURL { model.open($0) }
                #if os(macOS)
                // A link opens in the existing window rather than a new one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                #endif
                // Plans in a removed language stop reminding, and come back with it.
                .onChange(of: model.settings.profile?.learning) {
                    Task { await model.rescheduleReminders() }
                }
                #if DEBUG
                .task { await SelfTest.runIfRequested(app: model) }
                .task { await ReminderTest.sendIfRequested(app: model) }
                .task { ImportTest.openSampleIfRequested(app: model) }
                #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.importInbox()
                // Plans may have changed on another device.
                Task { await model.rescheduleReminders() }
            }
        }
    }
}
