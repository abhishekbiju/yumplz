import Foundation

/// Parses share-extension deep-link notifications into import sheet routes.
enum ImportDeepLinkRouter {

    struct Route: Equatable {
        var importURL: String?
        var pasteText: String?
        var videoPath: String?
        var autoStartImport: Bool
        var extractionMode: ShareExtractionMode
    }

    static func route(payload: String, userInfo: [AnyHashable: Any]? = nil) -> Route {
        let autoStart = (userInfo?[MealKitImportDeepLinkUserInfoKey.autoStart] as? Bool) ?? false
        let extractionMode: ShareExtractionMode
        if let raw = userInfo?[MealKitImportDeepLinkUserInfoKey.extractionMode] as? String,
           let mode = ShareExtractionMode(rawValue: raw) {
            extractionMode = mode
        } else {
            extractionMode = .captionOrDescription
        }

        if payload.hasPrefix("file://") {
            return Route(
                importURL: nil,
                pasteText: nil,
                videoPath: String(payload.dropFirst("file://".count)),
                autoStartImport: autoStart,
                extractionMode: extractionMode
            )
        }

        if ImportLinkParser.importableURL(from: payload) != nil {
            return Route(
                importURL: payload,
                pasteText: nil,
                videoPath: nil,
                autoStartImport: autoStart,
                extractionMode: extractionMode
            )
        }

        return Route(
            importURL: nil,
            pasteText: payload,
            videoPath: nil,
            autoStartImport: autoStart,
            extractionMode: extractionMode
        )
    }

    static func presentationRequest(payload: String, userInfo: [AnyHashable: Any]? = nil) -> ImportPresentationRequest {
        ImportPresentationRequest(route: route(payload: payload, userInfo: userInfo))
    }
}

/// Snapshot passed to the import sheet so deep-link values aren't cleared mid-presentation.
struct ImportPresentationRequest: Identifiable, Equatable {
    let id = UUID()
    let route: ImportDeepLinkRouter.Route

    static func == (lhs: ImportPresentationRequest, rhs: ImportPresentationRequest) -> Bool {
        lhs.id == rhs.id
    }
}
