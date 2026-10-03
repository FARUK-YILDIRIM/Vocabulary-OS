import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Entry point of the iOS Share extension: hosts the capture flow for the text another app shared
/// (SPEC C5). Saved words go to the App Group inbox, never to the synced store (ADR-002).
final class ShareViewController: UIViewController {
    private let session = ShareSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareCaptureView(session: session) { [weak self] outcome in
            self?.finish(outcome)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task {
            session.start(with: await Self.sharedText(in: items))
        }
    }

    private func finish(_ outcome: ShareCaptureView.Outcome) {
        switch outcome {
        case .done:
            extensionContext?.completeRequest(returningItems: nil)
        case .cancelled:
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }

    /// The first plain text among the shared items. Some apps only fill in the item's content text.
    private static func sharedText(in items: [NSExtensionItem]) async -> String {
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
