import SwiftUI

#if os(iOS)
import UIKit

/// Entry point of the Share extension on iPhone and iPad: hosts the capture flow for the shared text
/// (SPEC C5). Saved words go to the App Group inbox, never to the synced store (ADR-002).
final class ShareViewController: UIViewController {
    private let session = ShareSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareCaptureView(session: session) { [weak self] outcome in
            self?.extensionContext?.finish(outcome)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task {
            session.start(with: await SharedText.read(from: items))
        }
    }
}
#else
import AppKit

/// Entry point of the Share extension on the Mac: hosts the capture flow for the shared text
/// (SPEC C5). Saved words go to the App Group inbox, never to the synced store (ADR-002).
final class ShareViewController: NSViewController {
    private let session = ShareSession()

    override func loadView() {
        view = NSHostingView(rootView: ShareCaptureView(session: session) { [weak self] outcome in
            self?.extensionContext?.finish(outcome)
        })
        preferredContentSize = NSSize(width: 480, height: 560)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task {
            session.start(with: await SharedText.read(from: items))
        }
    }
}
#endif

extension NSExtensionContext {
    func finish(_ outcome: ShareCaptureView.Outcome) {
        switch outcome {
        case .done:
            completeRequest(returningItems: nil)
        case .cancelled:
            cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
