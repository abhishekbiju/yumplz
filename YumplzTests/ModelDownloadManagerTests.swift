import XCTest
@testable import Yumplz

/// Regression: driving a real import through an Xcode Canvas/Live Preview starts a
/// multi-gigabyte download + on-device LLM load inside the preview's constrained
/// process, which gets killed and shows "Preview crashed" with no diagnostics.
/// `ensureReady` must fail fast with a clear error instead of attempting the download.
final class ModelDownloadManagerTests: XCTestCase {

    @MainActor
    func testEnsureReady_throwsUnavailableInPreview_whenRunningInXcodePreview() async {
        setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
        defer { unsetenv("XCODE_RUNNING_FOR_PREVIEWS") }

        let manager = ModelDownloadManager()
        do {
            _ = try await manager.ensureReady(.llama3_2_3b)
            XCTFail("Expected unavailableInPreview to be thrown")
        } catch DownloadError.unavailableInPreview {
            // expected
        } catch {
            XCTFail("Expected unavailableInPreview, got \(error)")
        }
    }

    @MainActor
    func testIsRunningInXcodePreview_falseOutsidePreviewProcess() {
        unsetenv("XCODE_RUNNING_FOR_PREVIEWS")
        XCTAssertFalse(ModelDownloadManager.isRunningInXcodePreview)
    }
}
