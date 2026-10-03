import SwiftUI
import VocabularyCore

/// First launch: welcome, native language, learning languages (SPEC C1).
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Step] = []
    @State private var native = LanguageCatalog.suggestedNative(for: .current)
    @State private var learning: [LanguageCode] = []

    enum Step: Hashable {
        case native, learning
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStep { path.append(.native) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .native:
                        NativeLanguageStep(native: $native) { path.append(.learning) }
                    case .learning:
                        LearningLanguagesStep(native: native, learning: $learning, onFinish: finish)
                    }
                }
        }
        .onChange(of: native) {
            learning.removeAll { $0 == native }
        }
    }

    private func finish() {
        // The steps only offer valid choices, so this cannot fail; guard anyway rather than crash.
        guard let profile = try? LearnerProfile(native: native, learning: learning) else { return }
        model.settings.profile = profile
    }
}

private struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Learn words where you meet them")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        systemImage: "text.viewfinder",
                        title: "Capture in context",
                        detail: "From any app, a page of a book, or the things around you."
                    )
                    FeatureRow(
                        systemImage: "sparkles",
                        title: "Meaning in your language",
                        detail: "On-device AI by default, or the AI provider of your choice."
                    )
                    FeatureRow(
                        systemImage: "lock.icloud",
                        title: "Private by design",
                        detail: "Your words stay in your iCloud. No account, no tracking."
                    )
                }
                .frame(maxWidth: 460, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar { PrimaryButton("Get Started", action: onContinue) }
        }
    }
}

private struct FeatureRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NativeLanguageStep: View {
    @Binding var native: LanguageCode
    let onContinue: () -> Void

    var body: some View {
        LanguageList(languages: LanguageCatalog.all, isSelected: { $0 == native }, onSelect: { native = $0 })
            .navigationTitle("Your native language")
            .safeAreaInset(edge: .bottom) {
                BottomBar { PrimaryButton("Continue", action: onContinue) }
            }
    }
}

private struct LearningLanguagesStep: View {
    let native: LanguageCode
    @Binding var learning: [LanguageCode]
    let onFinish: () -> Void

    var body: some View {
        LanguageList(
            languages: LanguageCatalog.all.filter { $0 != native },
            isSelected: { learning.contains($0) },
            onSelect: toggle
        )
        .navigationTitle("Languages you're learning")
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                Text("Pick one or more. You can add languages later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PrimaryButton("Start Learning", action: onFinish)
                    .disabled(learning.isEmpty)
            }
        }
    }

    private func toggle(_ code: LanguageCode) {
        if let index = learning.firstIndex(of: code) {
            learning.remove(at: index)
        } else {
            learning.append(code)
        }
    }
}

/// Pins its content to the bottom of an onboarding step, above the scrolling list.
private struct BottomBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 8) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

/// The large call-to-action of an onboarding step.
private struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: 420)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

#Preview {
    OnboardingView().environment(AppModel.preview(profile: nil))
}
