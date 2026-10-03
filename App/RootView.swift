import SwiftUI

/// Shows onboarding until the learner has chosen their languages, then the main interface.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.settings.isOnboarded {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: model.settings.isOnboarded)
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }
}

#Preview("Onboarded") {
    RootView().environment(AppModel.preview())
}

#Preview("First launch") {
    RootView().environment(AppModel.preview(profile: nil))
}
