// Prints the window number of the app's main window, for `screencapture -l`. The window may be on
// another Space, for example while another app is full screen; it is captured all the same.
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Vocabulary-OS"
let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let window = windows.first { window in
    let bounds = window[kCGWindowBounds as String] as? [String: Any]
    return (window[kCGWindowOwnerName as String] as? String) == owner
        && (window[kCGWindowLayer as String] as? Int) == 0
        && (bounds?["Width"] as? Double ?? 0) > 100
        && (bounds?["Height"] as? Double ?? 0) > 100
}
if let number = window?[kCGWindowNumber as String] as? Int {
    print(number)
} else {
    exit(1)
}
