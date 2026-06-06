import Foundation
import Vision
import SwiftData
import os.log

private let log = Logger(subsystem: "com.abhishekbiju.mealkit", category: "Import")

// MARK: - Import pipeline state

enum ImportPhase: Equatable, Sendable {
    case idle
    case fetchingURL
    case extractingSocialContent
    case runningOCR
    case transcribingAudio
    case parsingWithAI
    case done
    case failed(String)

    var displayLabel: String {
        switch self {
        case .idle:                    return "Ready"
        case .fetchingURL:             return "Fetching page…"
        case .extractingSocialContent: return "Reading post content…"
        case .runningOCR:              return "Reading text…"
        case .transcribingAudio:       return "Transcribing audio…"
        case .parsingWithAI:           return "Parsing with AI…"
        case .done:                    return "Done"
        case .failed(let msg):         return "Error: \(msg)"
        }
    }

    var isWorking: Bool {
        switch self {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    /// Persisted on `Recipe.importPhaseRaw` for in-progress imports.
    var storageKey: String {
        switch self {
        case .idle: return "idle"
        case .fetchingURL: return "fetchingURL"
        case .extractingSocialContent: return "extractingSocialContent"
        case .runningOCR: return "runningOCR"
        case .transcribingAudio: return "transcribingAudio"
        case .parsingWithAI: return "parsingWithAI"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    static func from(storageKey: String) -> ImportPhase? {
        switch storageKey {
        case "idle": return .idle
        case "fetchingURL": return .fetchingURL
        case "extractingSocialContent": return .extractingSocialContent
        case "runningOCR": return .runningOCR
        case "transcribingAudio": return .transcribingAudio
        case "parsingWithAI": return .parsingWithAI
        case "done": return .done
        case "failed": return .failed("")
        default: return nil
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
    private var backgroundImportTask: Task<Void, Never>?

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
    func startImport(from source: ImportSource, extractionMode: ShareExtractionMode = .captionOrDescription) async {
        phase = .idle
        draft = nil

        do {
            draft = try await runPipeline(source: source, extractionMode: extractionMode)
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

    /// Creates a library placeholder and runs the import pipeline in the background.
    /// The sheet can dismiss immediately; `recipe` shows progress in the Library grid.
    func beginBackgroundImport(
        from source: ImportSource,
        in context: ModelContext,
        extractionMode: ShareExtractionMode = .captionOrDescription
    ) -> Recipe {
        let placeholder = Self.createPlaceholder(from: source, in: context)
        backgroundImportTask = Task { [weak self] in
            await self?.runBackgroundImport(
                from: source,
                recipe: placeholder,
                in: context,
                extractionMode: extractionMode
            )
        }
        return placeholder
    }

    func runBackgroundImport(
        from source: ImportSource,
        recipe: Recipe,
        in context: ModelContext,
        extractionMode: ShareExtractionMode = .captionOrDescription
    ) async {
        phase = .idle
        draft = nil
        syncImportPhase(.idle, to: recipe, in: context)

        do {
            let dto = try await runPipeline(
                source: source,
                extractionMode: extractionMode,
                progressRecipe: recipe,
                progressContext: context
            )
            draft = dto
            try apply(dto, to: recipe, in: context)
            phase = .done
        } catch {
            log.error("Background import failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
            markImportFailed(error.localizedDescription, on: recipe, in: context)
        }
    }

    // MARK: - Pipeline

    private func runPipeline(
        source: ImportSource,
        extractionMode: ShareExtractionMode,
        progressRecipe: Recipe? = nil,
        progressContext: ModelContext? = nil
    ) async throws -> ParsedRecipeDTO {
        func report(_ importPhase: ImportPhase) {
            phase = importPhase
            if let progressRecipe, let progressContext {
                syncImportPhase(importPhase, to: progressRecipe, in: progressContext)
            }
        }

        // Ensure the LLM is loaded before any inference step.
        try await ensureLLMReady()

        let importContext: RecipeImportContext
        switch source {
        case .url(let url):
            importContext = try await extractContext(
                from: url,
                extractionMode: extractionMode,
                report: report
            )

        case .photo(let data):
            report(.runningOCR)
            importContext = RecipeImportContext(cleanedText: try await recognizeText(in: data))

        case .videoURL(let url):
            report(.transcribingAudio)
            try await whisper.ensureReady()
            importContext = RecipeImportContext(cleanedText: try await whisper.transcribeVideoURL(url))

        case .pastedText(let raw):
            if let url = ImportLinkParser.importableURL(from: raw),
               SocialPlatformDetector.platform(for: url) != .other {
                importContext = try await extractContext(
                    from: url,
                    extractionMode: extractionMode,
                    report: report
                )
            } else {
                importContext = RecipeImportContext(cleanedText: raw)
            }
        }

        try validateRecipeText(importContext.cleanedText)

        report(.parsingWithAI)
        return try await inference.parseRecipe(from: importContext)
    }

    private func extractContext(
        from url: URL,
        extractionMode: ShareExtractionMode,
        report: (ImportPhase) -> Void
    ) async throws -> RecipeImportContext {
        switch extractionMode {
        case .fullPage:
            report(.fetchingURL)
            return RecipeImportContext(cleanedText: try await fetchRecipeText(from: url))
        case .captionOrDescription:
            report(.extractingSocialContent)
            let socialResult = try await SocialURLRouter.route(url: url)
            switch socialResult {
            case .recipeText(let context):
                return context
            case .needsVideoFile:
                throw ImportError.needsVideoFile
            case .useHTMLScrape:
                // TikTok serves a JS shell — scraping yields ~22 chars and always fails validation.
                if SocialPlatformDetector.platform(for: url) == .tiktok {
                    throw ImportError.insufficientContent
                }
                report(.fetchingURL)
                return RecipeImportContext(cleanedText: try await fetchRecipeText(from: url))
            }
        case .transcribeAudio:
            throw ImportError.insufficientContent
        }
    }

    private func syncImportPhase(_ importPhase: ImportPhase, to recipe: Recipe, in context: ModelContext) {
        switch importPhase {
        case .failed:
            break
        case .done:
            recipe.importPhaseRaw = nil
            recipe.importErrorMessage = nil
        default:
            recipe.importPhaseRaw = importPhase.storageKey
            recipe.importErrorMessage = nil
        }
        try? context.save()
    }

    private func markImportFailed(_ message: String, on recipe: Recipe, in context: ModelContext) {
        recipe.importPhaseRaw = ImportPhase.failed(message).storageKey
        recipe.importErrorMessage = message
        try? context.save()
    }

    static func createPlaceholder(from source: ImportSource, in context: ModelContext) -> Recipe {
        let recipe = Recipe(title: placeholderTitle(for: source))
        recipe.sourceKind = sourceKind(for: source)
        recipe.importSourceURL = sourceURL(for: source)
        recipe.importedAt = Date()
        recipe.importPhaseRaw = ImportPhase.idle.storageKey
        context.insert(recipe)
        try? context.save()
        return recipe
    }

    static func placeholderTitle(for source: ImportSource) -> String {
        switch source {
        case .url(let url):
            return displayHost(from: url)
        case .pastedText(let raw):
            if let url = ImportLinkParser.importableURL(from: raw) {
                return displayHost(from: url)
            }
            return "Importing recipe…"
        case .photo:
            return "Importing from photo…"
        case .videoURL:
            return "Importing from video…"
        }
    }

    private static func displayHost(from url: URL) -> String {
        let host = url.host?
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression) ?? "Recipe"
        return host
    }

    private static func sourceURL(for source: ImportSource) -> URL? {
        switch source {
        case .url(let url): return url
        case .pastedText(let raw): return ImportLinkParser.importableURL(from: raw)
        case .videoURL(let url): return url
        case .photo: return nil
        }
    }

    private static func sourceKind(for source: ImportSource) -> SourceKind {
        switch source {
        case .url: return .url
        case .photo: return .photo
        case .videoURL: return .video
        case .pastedText: return .paste
        }
    }

    private func validateRecipeText(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else {
            throw ImportError.insufficientContent
        }
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
        let recipe = Recipe(title: RecipeDisplayFormatter.cleanTitle(dto.title))
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
            let normalized = IngredientDisplayFormatter.normalizedOriginalText(for: ingDTO)
            let ing = Ingredient(originalText: normalized, orderIndex: i)
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

    /// Fills an existing placeholder `Recipe` with parsed import data.
    func apply(_ dto: ParsedRecipeDTO, to recipe: Recipe, in context: ModelContext) throws {
        recipe.title = RecipeDisplayFormatter.cleanTitle(dto.title)
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
        recipe.importedAt = recipe.importedAt ?? Date()
        recipe.importPhaseRaw = nil
        recipe.importErrorMessage = nil
        recipe.updatedAt = Date()

        for ingredient in recipe.ingredients ?? [] {
            context.delete(ingredient)
        }
        for step in recipe.steps ?? [] {
            context.delete(step)
        }

        for (i, ingDTO) in dto.ingredients.enumerated() {
            let normalized = IngredientDisplayFormatter.normalizedOriginalText(for: ingDTO)
            let ing = Ingredient(originalText: normalized, orderIndex: i)
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

        try context.save()
    }
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case httpError(Int)
    case decodingFailed
    case invalidImage
    case noTextFound
    case insufficientContent
    case needsVideoFile

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
        case .insufficientContent:
            return "Couldn't extract enough recipe text from this link. Try pasting the caption or sharing the video file."
        case .needsVideoFile:
            return "Instagram captions can't be read from a link. " +
                   "In Instagram, tap ··· → Save Video, then share the video file to MealKit."
        }
    }
}
