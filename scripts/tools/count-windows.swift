// Prints how many windows belong to the app with the given name (no screen capture involved).
// Windows on every Space count, so the check also passes while another app is full screen; the
// size filter leaves out the app's helper windows, which have no size.
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Vocabulary-OS"
let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let count = windows.filter { window in
    let bounds = window[kCGWindowBounds as String] as? [String: Any]
    return (window[kCGWindowOwnerName as String] as? String) == owner
        && (window[kCGWindowLayer as String] as? Int) == 0
        && (bounds?["Width"] as? Double ?? 0) > 100
        && (bounds?["Height"] as? Double ?? 0) > 100
}.count
print(count)
