import SwiftUI

enum AppTab: Hashable {
    case today, library, settings
}

/// The main navigation: a tab bar on iPhone, a sidebar on iPad and Mac.
struct MainView: View {
    @State private var selection = LaunchOptions().initialTab ?? .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack {
                    ContentUnavailableView(
                        "Nothing to review yet",
                        systemImage: "sun.max",
                        description: Text("Words you capture will be scheduled for review here.")
                    )
                    .navigationTitle("Today")
                }
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack {
                    ContentUnavailableView(
                        "No words yet",
                        systemImage: "books.vertical",
                        description: Text("Capture a word from a sentence to start your library.")
                    )
                    .navigationTitle("Library")
                }
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
