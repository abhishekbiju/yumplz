import Foundation

extension Recipe {

    /// True when the recipe has finished importing and can be opened.
    var isImportInteractive: Bool {
        importPhaseRaw == nil
    }

    var isImportInProgress: Bool {
        guard let raw = importPhaseRaw else { return false }
        return raw != ImportPhase.failed("").storageKey
    }

    var importFailed: Bool {
        importPhaseRaw == ImportPhase.failed("").storageKey
    }

    var importStatusLabel: String {
        if let importErrorMessage, importFailed {
            return importErrorMessage
        }
        guard let raw = importPhaseRaw,
              let phase = ImportPhase.from(storageKey: raw) else {
            return ""
        }
        return phase.displayLabel
    }
}
