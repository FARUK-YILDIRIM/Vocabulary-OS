import SwiftData
import SwiftUI

@main
struct VocabularyOSApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
                #if DEBUG
                .task { await SelfTest.runIfRequested(app: model) }
                #endif
        }
    }
}
