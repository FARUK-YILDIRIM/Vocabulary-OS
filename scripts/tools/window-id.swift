// Prints the window number of the app's first on-screen window, for `screencapture -l`.
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Vocabulary-OS"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let window = windows.first {
    ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0
}
if let number = window?[kCGWindowNumber as String] as? Int {
    print(number)
} else {
    exit(1)
}
