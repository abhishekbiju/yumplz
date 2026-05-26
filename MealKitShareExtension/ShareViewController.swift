import UIKit
import SwiftUI
import UniformTypeIdentifiers
import MobileCoreServices

// MARK: - ShareViewController

/// The principal class of the MealKit Share Extension.
///
/// Architecture: the extension is a **lightweight receiver only**. It:
///   1. Inspects the shared item (URL or video file).
///   2. If a video file: copies it into the App Group shared container.
///   3. Writes a `PendingImportItem` to the shared JSON queue.
///   4. Dismisses. The main app processes the queue on next foreground.
///
/// The LLM is NOT loaded in the extension — iOS caps extension memory at
/// ~120 MB and loading a 2 GB model would be immediately killed.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground

        let providers = (extensionContext?.inputItems as? [NSExtensionItem])
            .flatMap { $0.flatMap { $0.attachments ?? [] } } ?? []

        let hostingVC = UIHostingController(rootView: ShareExtensionView(
            itemProviders: providers,
            onComplete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(
                    withError: NSError(
                        domain: "com.abhishekbiju.mealkit.shareextension",
                        code: NSUserCancelledError
                    )
                )
            }
        ))

        addChild(hostingVC)
        view.addSubview(hostingVC.view)
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hostingVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingVC.didMove(toParent: self)
    }
}
