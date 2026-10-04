import SwiftUI
import VocabularyUI

/// Practice: quizzes on saved words (SPEC C8).
struct PracticeView: View {
    @State private var quiz: QuizSessionModel?
    @State private var refreshToken = UUID()

    var body: some View {
        NavigationStack {
            Form {
                QuizSetupView(refreshToken: refreshToken) { quiz = $0 }
            }
            .formStyle(.grouped)
            .navigationTitle("Practice")
        }
        .sheet(isPresented: isQuizzing, onDismiss: { refreshToken = UUID() }) {
            if let quiz {
                QuizSessionView(model: quiz) {
                    quiz.cancel()
                    self.quiz = nil
                }
            }
        }
    }

    private var isQuizzing: Binding<Bool> {
        Binding(get: { quiz != nil }, set: { if !$0 { quiz = nil } })
    }
}

#Preview {
    PracticeView().environment(AppModel.preview())
}
