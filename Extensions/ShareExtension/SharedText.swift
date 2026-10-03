import Foundation
import UniformTypeIdentifiers

/// Reads the text another app shared with the extension.
enum SharedText {
    /// The first plain text among the shared items. Some apps only fill in the item's content text.
    static func read(from items: [NSExtensionItem]) async -> String {
        let providers = items.flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await loadText(from: provider), !text.isEmpty {
                return text
            }
        }
        return items.lazy.compactMap { $0.attributedContentText?.string }.first { !$0.isEmpty } ?? ""
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadTransferable(type: String.self) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }
}
