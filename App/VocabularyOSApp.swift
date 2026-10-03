import SwiftData
import SwiftUI

@main
struct VocabularyOSApp: App {
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

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
