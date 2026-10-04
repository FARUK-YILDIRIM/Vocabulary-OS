import SwiftUI

enum AppTab: String, Hashable {
    case today, capture, practice, library, settings
}

/// The main navigation: a tab bar on iPhone, a sidebar on iPad and Mac.
struct MainView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var navigation = app.navigation
        TabView(selection: $navigation.tab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                TodayView()
            }
            Tab("Capture", systemImage: "text.viewfinder", value: AppTab.capture) {
                CaptureScreen()
            }
            Tab("Practice", systemImage: "graduationcap", value: AppTab.practice) {
                PracticeView()
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    MainView().environment(AppModel.preview())
}
