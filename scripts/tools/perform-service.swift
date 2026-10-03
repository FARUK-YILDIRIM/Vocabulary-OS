// Invokes a Services menu item with text, as choosing it in another app would (used by mac-smoke.sh).
// Usage: swift perform-service.swift "<service menu item>" "<text>"
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: perform-service.swift <service> <text>\n".utf8))
    exit(2)
}
let pasteboard = NSPasteboard.withUniqueName()
pasteboard.clearContents()
pasteboard.setString(arguments[1], forType: .string)
let performed = NSPerformService(arguments[0], pasteboard)
// The provider reads the pasteboard after this call returns, so keep it alive for a moment.
Thread.sleep(forTimeInterval: 3)
pasteboard.releaseGlobally()
print(performed ? "performed" : "failed")
