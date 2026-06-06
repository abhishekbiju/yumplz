import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ShareViewController

@MainActor
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
            },
            onOpenImport: { [weak self] sharedValue in
                self?.openMealKit(with: sharedValue)
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

    private func openMealKit(with sharedValue: String) {
        guard let url = ShareAppLauncher.importDeepLinkURL(for: sharedValue, autoStart: true) else { return }
        // NOTE: extensionContext.open() is NOT supported by Share extensions (only
        // Today/iMessage). It always returns false. The only mechanism that works is
        // walking the responder chain to the live UIApplication instance and calling
        // the MODERN open(_:options:completionHandler:). The deprecated single-arg
        // `openURL:` selector stopped working in iOS 18.
        _ = openViaResponderChain(url)
    }

    @discardableResult
    private func openViaResponderChain(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return true
            }
            responder = current.next
        }
        return false
    }
}
