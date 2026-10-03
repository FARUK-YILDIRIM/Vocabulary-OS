import SwiftUI

/// Temporary root screen until onboarding and the main navigation exist (tasks T04, T11).
struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "Vocabulary-OS",
            systemImage: "text.book.closed",
            description: Text("Capture words in context. Coming together, one task at a time.")
        )
        .frame(minWidth: 320, minHeight: 240)
    }
}

#Preview {
    RootView()
}
