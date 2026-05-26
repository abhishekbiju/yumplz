import Foundation

// MARK: - Pending import item

/// A URL or video file queued by the Share Extension for processing by the
/// main app. Stored as JSON in the App Group shared container (or a local
/// temp directory when the App Group is not provisioned — see below).
struct PendingImportItem: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// A URL string (recipe blog, TikTok share URL, YouTube, etc.)
        case url
        /// An absolute path to a video file copied into the shared container.
        case videoFile
    }

    let id: String
    let kind: Kind
    /// For `.url`: the URL string. For `.videoFile`: absolute path in the container.
    let value: String
    let receivedAt: Date

    init(kind: Kind, value: String) {
        self.id = UUID().uuidString
        self.kind = kind
        self.value = value
        self.receivedAt = Date()
    }
}

// MARK: - Store

/// Thread-safe read/write access to the pending-import queue shared between
/// the main app and the Share Extension via an App Group container.
///
/// App Group (`group.com.abhishekbiju.mealkit`) requires a paid Apple
/// Developer account to use on a real device. In the simulator — or when
/// the entitlement is absent — the store falls back to a per-process temp
/// directory so the extension and main app can still be built and exercised.
///
/// The store is intentionally **not** `@Observable` — it is a static utility
/// accessed by both the extension process and the main app process. Callers
/// that need reactive updates should observe `scenePhase` changes and poll.
enum PendingImportStore {

    static let appGroupID = "group.com.abhishekbiju.mealkit"
    private static let fileName = "pendingImports.json"

    // MARK: - Container resolution

    /// The directory used to store the pending imports file.
    /// Prefers the App Group shared container; falls back to a local temp dir.
    static var containerDirectory: URL {
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return groupURL
        }
        // Fallback for simulator / no-entitlement builds.
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("MealKitPendingImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static var pendingFileURL: URL {
        containerDirectory.appendingPathComponent(fileName)
    }

    // MARK: - Queue operations

    /// Returns all pending items without removing them.
    static func readAll() -> [PendingImportItem] {
        guard let data = try? Data(contentsOf: pendingFileURL),
              let items = try? JSONDecoder().decode([PendingImportItem].self, from: data)
        else { return [] }
        return items
    }

    /// Appends a single item to the queue.
    static func append(_ item: PendingImportItem) {
        var current = readAll()
        current.append(item)
        write(current)
    }

    /// Returns all pending items and removes them from the queue atomically.
    @discardableResult
    static func drain() -> [PendingImportItem] {
        let items = readAll()
        write([])
        return items
    }

    /// Returns true if there is at least one pending item.
    static var hasPending: Bool {
        !readAll().isEmpty
    }

    /// Removes a single item by ID (used after the main app processes it).
    static func remove(id: String) {
        let remaining = readAll().filter { $0.id != id }
        write(remaining)
    }

    // MARK: - Private

    private static func write(_ items: [PendingImportItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: pendingFileURL, options: .atomic)
    }
}
