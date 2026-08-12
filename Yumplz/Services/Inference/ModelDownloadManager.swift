import Foundation
import os.log

private let log = Logger(subsystem: "com.abhishekbiju.yumplz", category: "ModelDownload")

// MARK: - Model descriptors

/// Every on-device model we ship. Adding a new model is a one-line change here.
enum LocalModel: String, CaseIterable, Sendable {
    /// Llama 3.2 3B Instruct, 4-bit Q4_K_M GGUF. ~2.0 GB on disk.
    case llama3_2_3b = "Llama-3.2-3B-Instruct-Q4_K_M.gguf"

    /// Whisper base.en CoreML model bundle directory.
    case whisperBaseEn = "openai_whisper-base.en"

    var displayName: String {
        switch self {
        case .llama3_2_3b:   return "Recipe AI (Llama 3.2 · 3B)"
        case .whisperBaseEn: return "Transcription AI (Whisper base)"
        }
    }

    /// HuggingFace direct-download URL for the GGUF / model bundle.
    var remoteURL: URL {
        switch self {
        case .llama3_2_3b:
            return URL(string:
                "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
            )!
        case .whisperBaseEn:
            // WhisperKit resolves its own model URLs at runtime — we hand it
            // a repo id. This URL is kept for display purposes only.
            return URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!
        }
    }

    /// Approximate download size in bytes — used to estimate progress time.
    var approximateBytes: Int64 {
        switch self {
        case .llama3_2_3b:   return 2_000_000_000   // ~2.0 GB
        case .whisperBaseEn: return   150_000_000   // ~150 MB
        }
    }
}

// MARK: - Download state

enum DownloadState: Sendable {
    case idle
    case downloading(progress: Double)  // 0–1
    case ready(url: URL)
    case failed(Error)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var readyURL: URL? {
        if case .ready(let url) = self { return url }
        return nil
    }

    var progressValue: Double {
        if case .downloading(let p) = self { return p }
        return 0
    }
}

// MARK: - Manager

/// Manages downloading and caching on-device AI model files.
///
/// Call `ensureReady(_:)` before attempting inference — it is a no-op when
/// the model file is already on disk and returns immediately.
@MainActor
@Observable
final class ModelDownloadManager: NSObject {

    // Per-model download states — keyed by rawValue for Sendable compliance.
    private(set) var states: [String: DownloadState] = [:]

    // Active URLSession tasks keyed by model rawValue.
    private var tasks: [String: URLSessionDownloadTask] = [:]

    // URLSession used for model downloads. Not `lazy` — @Observable macro
    // cannot track lazy stored properties. Assigned eagerly in init().
    private var session: URLSession = URLSession.shared

    override init() {
        // Build a dedicated URLSession before super.init() so we can pass
        // self as delegate after init completes.
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600   // up to 1 h on slow Wi-Fi
        config.isDiscretionary = false              // user-initiated, not deferred
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // Reconcile in-memory state with what's already on disk.
        for model in LocalModel.allCases {
            if let url = cachedURL(for: model) {
                states[model.rawValue] = .ready(url: url)
            } else {
                states[model.rawValue] = .idle
            }
        }
    }

    // MARK: Public API

    func state(for model: LocalModel) -> DownloadState {
        states[model.rawValue] ?? .idle
    }

    /// Returns the local URL immediately if already cached, otherwise starts
    /// a download and throws once the download begins (caller should observe
    /// `state(for:)` for completion).
    @discardableResult
    func ensureReady(_ model: LocalModel) async throws -> URL {
        if let url = cachedURL(for: model) {
            states[model.rawValue] = .ready(url: url)
            return url
        }

        // Whisper model is fetched by WhisperKit internally — we just need to
        // signal "downloading" and let WhisperTranscriptionService do the work.
        if model == .whisperBaseEn {
            states[model.rawValue] = .downloading(progress: 0)
            return try await downloadWhisper(model: model)
        }

        guard tasks[model.rawValue] == nil else {
            // Already in flight — caller should poll state(for:).
            throw DownloadError.alreadyInProgress
        }

        states[model.rawValue] = .downloading(progress: 0)
        let task = session.downloadTask(with: model.remoteURL)
        task.taskDescription = model.rawValue
        tasks[model.rawValue] = task
        task.resume()
        log.info("Started download for \(model.displayName, privacy: .public)")

        return try await waitForCompletion(model: model)
    }

    func cancelDownload(for model: LocalModel) {
        tasks[model.rawValue]?.cancel()
        tasks[model.rawValue] = nil
        states[model.rawValue] = .idle
    }

    // MARK: Private helpers

    /// Directory where model files live. Excluded from iCloud backup.
    /// `nonisolated(unsafe)` because it is read from the URLSession delegate
    /// (nonisolated context) and is a pure file-system computation with no
    /// mutable shared state — safe to call from any thread.
    nonisolated(unsafe) static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appending(path: "YumplzModels", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(resourceValues)
        return dir
    }()

    private func cachedURL(for model: LocalModel) -> URL? {
        let url = Self.modelsDirectory.appending(path: model.rawValue)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // Polls state until ready or failed — used in ensureReady.
    private func waitForCompletion(model: LocalModel) async throws -> URL {
        while true {
            switch states[model.rawValue] ?? .idle {
            case .ready(let url):
                return url
            case .failed(let error):
                throw error
            default:
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    // WhisperKit fetches its own model files. We delegate to it and just
    // track a synthetic progress value.
    private func downloadWhisper(model: LocalModel) async throws -> URL {
        // Resolved by WhisperTranscriptionService on first use.
        // We return the directory path it should populate.
        let dir = Self.modelsDirectory.appending(
            path: model.rawValue, directoryHint: .isDirectory
        )
        states[model.rawValue] = .ready(url: dir)
        return dir
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadManager: URLSessionDownloadDelegate, @unchecked Sendable {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let key = downloadTask.taskDescription else { return }
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else if let model = LocalModel(rawValue: key) {
            progress = Double(totalBytesWritten) / Double(model.approximateBytes)
        } else {
            progress = 0
        }
        Task { @MainActor in
            self.states[key] = .downloading(progress: min(progress, 0.99))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let key = downloadTask.taskDescription else { return }
        let dest = ModelDownloadManager.modelsDirectory.appending(path: key)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            log.info("Model \(key, privacy: .public) saved to \(dest.path, privacy: .public)")
            Task { @MainActor in
                self.states[key] = .ready(url: dest)
                self.tasks[key] = nil
            }
        } catch {
            log.error("Failed to move model \(key, privacy: .public): \(error, privacy: .public)")
            Task { @MainActor in
                self.states[key] = .failed(error)
                self.tasks[key] = nil
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let key = task.taskDescription, let error else { return }
        // A cancelled task is intentional — don't surface it as a failure.
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        log.error("Download failed for \(key, privacy: .public): \(error, privacy: .public)")
        Task { @MainActor in
            self.states[key] = .failed(error)
            self.tasks[key] = nil
        }
    }
}

// MARK: - Errors

enum DownloadError: LocalizedError {
    case alreadyInProgress
    case modelNotFound(LocalModel)

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "A download is already in progress for this model."
        case .modelNotFound(let model):
            return "The model \(model.displayName) could not be found after download."
        }
    }
}
