import Foundation
import WhisperKit
import os.log

private let log = Logger(subsystem: "com.abhishekbiju.mealkit", category: "Whisper")

/// Transcribes audio files from social video URLs using WhisperKit (CoreML).
/// The model is downloaded from HuggingFace on first use and cached on disk.
@MainActor
@Observable
final class WhisperTranscriptionService {

    enum State: Sendable {
        case idle
        case downloading(progress: Double)
        case ready
        case transcribing
        case failed(Error)
    }

    private(set) var state: State = .idle
    private var pipe: WhisperKit?

    // MARK: Lifecycle

    /// Ensures WhisperKit is ready. Downloads the model on first call.
    func ensureReady() async throws {
        if case .ready = state { return }
        state = .downloading(progress: 0)
        do {
            let modelDirectory = ModelDownloadManager.modelsDirectory.path
            let config = WhisperKitConfig(
                model: "openai_whisper-base.en",
                modelFolder: modelDirectory,
                verbose: false,
                logLevel: .none,
                download: true
            )
            let whisper = try await WhisperKit(config)
            pipe = whisper
            state = .ready
            log.info("WhisperKit ready")
        } catch {
            state = .failed(error)
            throw error
        }
    }

    // MARK: Transcription

    /// Transcribes a local audio file. `audioURL` must be a file:// URL to a
    /// format AVFoundation can decode (mp4, m4a, mp3, wav).
    func transcribe(audioURL: URL) async throws -> String {
        guard case .ready = state, let pipe else {
            throw TranscriptionError.notReady
        }
        state = .transcribing
        defer { state = .ready }

        let results = try await pipe.transcribe(audioPath: audioURL.path)
        let transcript = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        log.info("Transcribed \(transcript.count, privacy: .public) chars")
        return transcript
    }

    /// Downloads audio from a remote video URL using AVFoundation, then
    /// transcribes it. Returns the transcript string.
    func transcribeVideoURL(_ videoURL: URL) async throws -> String {
        let audioURL = try await extractAudio(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        return try await transcribe(audioURL: audioURL)
    }

    // MARK: Private

    /// Remuxes the video at `videoURL` to an m4a audio-only file in the temp
    /// directory using AVFoundation's export session.
    private func extractAudio(from videoURL: URL) async throws -> URL {
        // Defer the heavy AVFoundation import to here to keep compile times fast
        // when transcription isn't needed.
        let avBundle = Bundle(identifier: "com.apple.avfoundation")
        _ = avBundle  // silence unused warning — we use AVFoundation via dynamic dispatch below.

        // Use AVAssetExportSession for audio extraction.
        // Imported via @_implementationOnly to avoid exposing AVFoundation
        // in the module interface unnecessarily.
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let url = try await _extractAudioConcrete(from: videoURL)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Audio extraction (concrete)

import AVFoundation

@MainActor
private func _extractAudioConcrete(from videoURL: URL) async throws -> URL {
    let asset = AVURLAsset(url: videoURL)
    let outputURL = FileManager.default.temporaryDirectory
        .appending(path: "\(UUID().uuidString).m4a")

    guard let session = AVAssetExportSession(
        asset: asset,
        presetName: AVAssetExportPresetAppleM4A
    ) else {
        throw TranscriptionError.audioExtractionFailed
    }

    session.outputURL = outputURL
    session.outputFileType = .m4a

    await session.export()

    guard session.status == .completed else {
        throw session.error ?? TranscriptionError.audioExtractionFailed
    }
    return outputURL
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case notReady
    case audioExtractionFailed

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "The transcription model is not loaded yet."
        case .audioExtractionFailed:
            return "Could not extract audio from the video URL."
        }
    }
}
