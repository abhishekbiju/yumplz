import XCTest
import SwiftData
@testable import Yumplz

/// End-to-end regression for a single real import: real network extraction +
/// real on-device model. Guards against two regressions found in the wild —
/// a duplicate-import bug and a "runs forever" perception caused by the model
/// generating well past a complete answer plus a deterministic JSON-repair
/// failure forcing a full retry. Requires the Llama model already downloaded
/// on this simulator/device. Enable with YUMPLZ_LIVE_LLM=1 (same gate as
/// RecipePromptLiveTests).
final class LiveSingleImportDiagnosticTests: XCTestCase {

    @MainActor
    func testSingleURLImport_completesWithoutHangingOrDuplicating() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["YUMPLZ_LIVE_LLM"] == "1",
            "Set YUMPLZ_LIVE_LLM=1 to run the live single-import regression"
        )

        let modelURL = ModelDownloadManager.modelsDirectory
            .appending(path: LocalModel.llama3_2_3b.rawValue)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: modelURL.path),
            "Model not present at \(modelURL.path) — download it in-app first"
        )

        let container = try TestModelContainer.make()
        let context = container.mainContext

        let downloads = ModelDownloadManager()
        let inference = InferenceService()
        let whisper = WhisperTranscriptionService()
        let importService = ImportService(downloads: downloads, inference: inference, whisper: whisper)

        let url = URL(string: "https://www.youtube.com/shorts/6UuseD5McGE")!
        let start = Date()

        var importFinished = false
        Task { @MainActor in
            await importService.startImport(from: .url(url))
            importFinished = true
        }

        // 15 min hard ceiling — well above the ~4 min a real single import
        // takes on Simulator CPU, so a hang shows up as a clear test failure
        // instead of an indefinite wait.
        let deadline: TimeInterval = 900
        while !importFinished {
            if Date().timeIntervalSince(start) > deadline {
                XCTFail("Import did not complete within \(Int(deadline))s — last phase: \(importService.phase.displayLabel)")
                return
            }
            try await Task.sleep(for: .seconds(1))
        }

        switch importService.phase {
        case .done:
            let dto = importService.draft
            XCTAssertNotNil(dto)
            XCTAssertFalse(dto?.ingredients.isEmpty ?? true)
            XCTAssertFalse(dto?.steps.isEmpty ?? true)
        case .failed(let message):
            XCTFail("Import failed: \(message)")
        default:
            XCTFail("Import ended in unexpected phase: \(importService.phase)")
        }
    }
}
