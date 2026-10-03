#if os(macOS)
import AppKit
import SwiftUI
import VocabularyUI

/// Services → "Capture in Vocabulary-OS": captures text selected in any Mac app (SPEC C5).
///
/// AppKit delivers service requests to `NSApplication.servicesProvider`, outside SwiftUI's scenes,
/// so the capture window is an AppKit window that hosts the shared capture flow. It runs inside the
/// app, so it needs no App Group and works in unsigned builds too.
final class ServicesProvider: NSObject {
    private let app: AppModel
    private var window: NSWindow?

    init(app: AppModel) {
        self.app = app
    }

    /// The `NSMessage` of the service declared under `NSServices` in Info.plist.
    @objc func captureText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = String(localized: "Select some text to capture.") as NSString
            return
        }
        showCapture(of: text)
    }

    /// Opens the capture window with the text, replacing a capture still open in it.
    func showCapture(of text: String) {
        let model = CaptureModel(
            text: text,
            captureSource: .services,
            settings: app.settings,
            destination: LibraryCaptureDestination(repository: app.repository),
            insightService: app.makeInsightService
        )
        let window = window ?? makeWindow()
        let size = window.contentLayoutRect.size
        window.contentViewController = NSHostingController(rootView: QuickCaptureView(model: model).environment(app))
        // Assigning a view controller resizes the window to the controller's initial view size.
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Capture")
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
#endif
