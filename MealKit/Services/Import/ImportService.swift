import Foundation
import Vision
import SwiftData
import os.log

private let log = Logger(subsystem: "com.abhishekbiju.mealkit", category: "Import")

// MARK: - Import pipeline state

enum ImportPhase: Equatable, Sendable {
    case idle
    case fetchingURL
    case runningOCR
    case transcribingAudio
    case parsingWithAI
    case done
    case failed(String)

    var displayLabel: String {
        switch self {
        case .idle:                return "Ready"
        case .fetchingURL:         return "Fetching page…"
        case .runningOCR:          return "Reading text…"
        case .transcribingAudio:   return "Transcribing audio…"
        case .parsingWithAI:       return "Parsing with AI…"
        case .done:                return "Done"
        case .failed(let msg):     return "Error: \(msg)"
        }
    }

    var isWorking: Bool {
        switch self {
        case .idle, .done, .failed: return false
        default: return true
        }
    }
}

// MARK: - Import source

enum ImportSource: Sendable {
    case url(URL)
    case photo(Data)         // JPEG/PNG data from camera or photo library
    case videoURL(URL)       // Social video URL — audio extracted + transcribed
    case pastedText(String)
}

// MARK: - ImportService

/// Orchestrates the import pipeline for all five source kinds.
/// Produces a `ParsedRecipeDTO` that the caller reviews and saves.
///
/// Thread model: all published state is `@MainActor`. Heavy work (network,
/// OCR, inference) is performed on background tasks and results marshalled back.
@MainActor
@Observable
final class ImportService {

    private(set) var phase: ImportPhase = .idle
    private(set) var draft: ParsedRecipeDTO?

    private let downloads: ModelDownloadManager
    private let inference: InferenceService
    private let whisper: WhisperTranscriptionService

    init(
        downloads: ModelDownloadManager,
        inference: InferenceService,
        whisper: WhisperTranscriptionService
    ) {
        self.downloads = downloads
        self.inference = inference
        self.whisper = whisper
    }

    // MARK: Public

    /// Main entry point. Runs the full pipeline and sets `draft` on success.
    func startImport(from source: ImportSource) async {
        phase = .idle
        draft = nil

        do {
            draft = try await runPipeline(source: source)
            phase = .done
        } catch {
            log.error("Import failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    func reset() {
        phase = .idle
        draft = nil
    }

    // MARK: - Pipeline

    private func runPipeline(source: ImportSource) async throws -> ParsedRecipeDTO {
        // Ensure the LLM is loaded before any inference step.
        try await ensureLLMReady()

        let text: String
        switch source {
        case .url(let url):
            phase = .fetchingURL
            text = try await fetchRecipeText(from: url)

        case .photo(let data):
            phase = .runningOCR
            text = try await recognizeText(in: data)

        case .videoURL(let url):
            phase = .transcribingAudio
            try await whisper.ensureReady()
            text = try await whisper.transcribeVideoURL(url)

        case .pastedText(let raw):
            text = raw
        }

        phase = .parsingWithAI
        return try await inference.parseRecipe(from: text)
    }

    // MARK: - LLM readiness

    private func ensureLLMReady() async throws {
        guard case .ready = inference.state else {
            let modelURL = try await downloads.ensureReady(.llama3_2_3b)
            try await inference.load(modelURL: modelURL)
            return
        }
    }

    // MARK: - URL fetch

    /// Fetches a URL and strips HTML tags to return readable recipe text.
    private func fetchRecipeText(from url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("MealKit/1.0 (iOS recipe importer)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let html = String(data: data, encoding: .utf8) ??
                         String(data: data, encoding: .isoLatin1) else {
            throw ImportError.decodingFailed
        }
        return stripHTML(html)
    }

    private func stripHTML(_ html: String) -> String {
        // Remove script / style blocks entirely first.
        var text = html
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>",
                                  with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>",
                                  with: "", options: .regularExpression)
        // Strip remaining tags.
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Decode common HTML entities.
        text = text
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        // Collapse whitespace.
        return text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - OCR

    /// Uses Apple Vision (on-device) to extract text from image data.
    private func recognizeText(in imageData: Data) async throws -> String {
        guard let cgImage = makeCGImage(from: imageData) else {
            throw ImportError.invalidImage
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func makeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }
}

// MARK: - Save helper

extension ImportService {

    /// Converts a confirmed `ParsedRecipeDTO` into SwiftData models and inserts
    /// them into the given context. Returns the newly created `Recipe`.
    @discardableResult
    func save(_ dto: ParsedRecipeDTO, in context: ModelContext) throws -> Recipe {
        let recipe = Recipe(title: dto.title)
        recipe.summary = dto.summary
        recipe.servings = max(1, dto.servings)
        recipe.prepTimeSeconds = dto.prepTimeMinutes.map { $0 * 60 }
        recipe.cookTimeSeconds = dto.cookTimeMinutes.map { $0 * 60 }
        recipe.tags = dto.tags
        recipe.cuisine = dto.cuisine
        recipe.dietaryTags = dto.dietaryTags
        recipe.nutritionCalories = dto.nutrition?.calories
        recipe.nutritionProteinGrams = dto.nutrition?.proteinGrams
        recipe.nutritionCarbsGrams = dto.nutrition?.carbsGrams
        recipe.nutritionFatGrams = dto.nutrition?.fatGrams
        recipe.sourceKind = .manual  // refined by callers that know the source
        recipe.importedAt = Date()

        context.insert(recipe)

        for (i, ingDTO) in dto.ingredients.enumerated() {
            let ing = Ingredient(originalText: ingDTO.originalText, orderIndex: i)
            ing.parsedQuantity = ingDTO.quantity
            ing.parsedUnitRaw = ingDTO.unit
            ing.parsedName = ingDTO.name.isEmpty ? nil : ingDTO.name
            ing.parsedPrep = ingDTO.prep
            ing.storeCategoryRaw = ingDTO.storeCategory
            ing.recipe = recipe
            context.insert(ing)
        }

        for (i, stepDTO) in dto.steps.enumerated() {
            let step = Step(
                text: stepDTO.text,
                orderIndex: i,
                timerSeconds: stepDTO.timerSeconds,
                isSectionHeader: stepDTO.isSectionHeader
            )
            step.recipe = recipe
            context.insert(step)
        }

        return recipe
    }
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case httpError(Int)
    case decodingFailed
    case invalidImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "The page returned HTTP \(code). Check the URL and try again."
        case .decodingFailed:
            return "Could not read the page content."
        case .invalidImage:
            return "The selected image could not be processed."
        case .noTextFound:
            return "No readable text was found in the image."
        }
    }
}
