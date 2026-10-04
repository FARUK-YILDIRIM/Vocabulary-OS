import SwiftUI

/// Shows onboarding until the learner has chosen their languages, then the main interface.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let storeError = model.storeError {
                StoreErrorView(message: storeError)
            } else if model.settings.isOnboarded {
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

/// Shown instead of the app when the word store can't be opened: going on, the learner's new words
/// would go into a stand-in store that disappears at the next launch (code review).
private struct StoreErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Your Library Couldn't Be Opened", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 12) {
                Text("Vocabulary-OS couldn't open your saved words, so it shows nothing rather than risk losing what you add. Quit the app and open it again. If this keeps happening, restart your device or free up some storage.")
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("store-error")
    }
}

#Preview("Onboarded") {
    RootView().environment(AppModel.preview())
}

#Preview("First launch") {
    RootView().environment(AppModel.preview(profile: nil))
}
