import Foundation

/// Maps pending share-extension imports into main-app deep-link deliveries.
enum ShareImportDelivery {

    struct DeliveredImport: Equatable, Sendable {
        let payload: String
        let autoStartImport: Bool
        let extractionMode: ShareExtractionMode
        let importKind: PendingImportItem.Kind
    }

    /// Drains the shared queue and returns structured deliveries for the main app.
    static func drainAndDeliver() -> [DeliveredImport] {
        PendingImportStore.drain().map { deliveredImport(from: $0) }
    }

    static func deliveredImport(from item: PendingImportItem) -> DeliveredImport {
        DeliveredImport(
            payload: payloadString(for: item),
            autoStartImport: item.autoStartImport,
            extractionMode: item.extractionMode,
            importKind: item.kind
        )
    }

    static func payloadString(for item: PendingImportItem) -> String {
        switch item.kind {
        case .url, .plainText:
            return item.value
        case .videoFile:
            return "file://\(item.value)"
        }
    }

    /// Deep link that foregrounds MealKit; queue is drained separately on appear.
    static var launchURL: URL {
        ShareAppLauncher.launchURL
    }

    static func makeDeepLinkNotification(for item: PendingImportItem) -> (name: Notification.Name, object: String, userInfo: [String: Any]) {
        (
            name: .mealKitImportDeepLink,
            object: payloadString(for: item),
            userInfo: [
                MealKitImportDeepLinkUserInfoKey.autoStart: item.autoStartImport,
                MealKitImportDeepLinkUserInfoKey.extractionMode: item.extractionMode.rawValue,
                MealKitImportDeepLinkUserInfoKey.importKind: item.kind.rawValue,
            ]
        )
    }

    /// Drains queue and posts deep-link notifications. Call on foreground and on first appear.
    static func deliverPendingImports(selectLibraryTab: @escaping () -> Void = {}) {
        let items = PendingImportStore.drain()
        guard !items.isEmpty else { return }

        selectLibraryTab()

        for (index, item) in items.enumerated() {
            let delay = Double(index) * 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let note = makeDeepLinkNotification(for: item)
                storePendingDeepLink(payload: note.object, userInfo: note.userInfo)
                NotificationCenter.default.post(name: note.name, object: note.object, userInfo: note.userInfo)
            }
        }
    }

    // MARK: - Pending deep link (survives cold launch before LibraryView mounts)

    nonisolated(unsafe) private static var pendingDeepLink: ImportPresentationRequest?

    static func storePendingDeepLink(payload: String, userInfo: [AnyHashable: Any]?) {
        pendingDeepLink = ImportDeepLinkRouter.presentationRequest(payload: payload, userInfo: userInfo)
    }

    @discardableResult
    static func consumePendingDeepLink() -> ImportPresentationRequest? {
        defer { pendingDeepLink = nil }
        return pendingDeepLink
    }

    /// Clears the in-memory pending deep link without consuming a route.
    /// Used when a live notification already delivered the same payload.
    static func clearPendingDeepLink() {
        pendingDeepLink = nil
    }

    /// Non-consuming check — lets the host select the Library tab so the consuming
    /// view (LibraryView.onAppear) actually mounts on a cold launch.
    static var hasPendingDeepLink: Bool { pendingDeepLink != nil }
}
