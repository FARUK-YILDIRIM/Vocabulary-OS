// Prints how many on-screen windows belong to the app with the given name (no screen capture involved).
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Vocabulary-OS"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let count = windows.filter {
    ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0
}.count
print(count)
