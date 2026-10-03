#if os(macOS)
import AppKit
#endif
import SwiftData
import SwiftUI

@main
struct VocabularyOSApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel.live()
        _model = State(initialValue: model)
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
                #if DEBUG
                .task { await SelfTest.runIfRequested(app: model) }
                #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.importInbox()
            }
        }
    }
}
