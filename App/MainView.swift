import SwiftUI

enum AppTab: String, Hashable {
    case today, capture, library, settings
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
            Tab("Capture", systemImage: "text.viewfinder", value: AppTab.capture) {
                CaptureScreen()
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
