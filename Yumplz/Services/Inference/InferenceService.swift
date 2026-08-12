import Foundation
import LlamaSwift   // @_exported @preconcurrency import llama — raw llama.cpp C API (b9319+)
import os.log

private let log = Logger(subsystem: "com.abhishekbiju.yumplz", category: "Inference")

// MARK: - InferenceService

/// High-level façade over the on-device Llama 3.2 3B model.
/// State is published on `@MainActor`; heavy work is serialised on `LlamaActor`.
@MainActor
@Observable
final class InferenceService {

    enum State: Sendable {
        case idle
        case loading
        case ready
        case failed(Error)
    }

    private(set) var state: State = .idle
    private let runner = LlamaActor()

    // MARK: Lifecycle

    func load(modelURL: URL) async throws {
        state = .loading
        do {
            try await runner.load(modelURL: modelURL)
            state = .ready
            log.info("InferenceService ready — \(modelURL.lastPathComponent, privacy: .public)")
        } catch {
            state = .failed(error)
            throw error
        }
    }

    func unload() async {
        await runner.unload()
        state = .idle
    }

    // MARK: Completions

    func complete(
        system: String = RecipePrompts.systemPrompt,
        prompt: String,
        maxNewTokens: Int = 2048,
        temperature: Float = 0.0
    ) async throws -> String {
        guard case .ready = state else { throw InferenceError.notLoaded }
        let formatted = llamaChatPrompt(system: system, user: prompt)
        return try await runner.complete(
            prompt: formatted,
            maxNewTokens: maxNewTokens,
            temperature: temperature
        )
    }

    // MARK: High-level helpers

    func parseRecipe(from context: RecipeImportContext) async throws -> ParsedRecipeDTO {
        let payload = context.llmPayload
        // Long social captions need a smaller prompt so more context remains for JSON output.
        let compactFirst = payload.count > 900
        let primaryPrompt = compactFirst
            ? RecipePrompts.compactRecipeExtractionPrompt(from: payload)
            : RecipePrompts.recipeExtractionPrompt(from: payload)
        let retryPrompt = compactFirst
            ? RecipePrompts.recipeExtractionPrompt(from: payload)
            : RecipePrompts.compactRecipeExtractionPrompt(from: payload)

        let primaryRaw = try await complete(prompt: primaryPrompt, maxNewTokens: 1800)
        do {
            let dto = try RecipeJSONParser.parseRecipeDTO(from: primaryRaw)
            try validateParsedRecipe(dto)
            return RecipeImportSanitizer.sanitize(dto, context: context)
        } catch {
            log.warning("Primary recipe parse failed (\(String(describing: error), privacy: .public)); retrying alternate prompt")
            let retryRaw = try await complete(prompt: retryPrompt, maxNewTokens: 1800)
            let dto = try RecipeJSONParser.parseRecipeDTO(from: retryRaw)
            try validateParsedRecipe(dto)
            return RecipeImportSanitizer.sanitize(dto, context: context)
        }
    }

    /// Backward-compatible entry for callers that only have raw text.
    func parseRecipe(from text: String) async throws -> ParsedRecipeDTO {
        try await parseRecipe(from: RecipeImportContext(cleanedText: text))
    }

    private func validateParsedRecipe(_ dto: ParsedRecipeDTO) throws {
        guard !dto.ingredients.isEmpty else {
            throw InferenceError.malformedResponse
        }
        guard !dto.steps.isEmpty else {
            throw InferenceError.malformedResponse
        }
    }

    private func llamaChatPrompt(system: String, user: String) -> String {
        LlamaChatFormatting.prompt(system: system, user: user)
    }
}

// MARK: - LlamaActor

/// Owns the llama.cpp model + context lifecycle on a private serial actor.
/// All llama.cpp C calls happen here — the actor guarantees single-threaded access.
private actor LlamaActor {

    // Opaque C pointers — safe here because the actor serialises all access.
    private var model: OpaquePointer?   // llama_model *
    private var ctx: OpaquePointer?     // llama_context *

    // llama_sampler is a complete struct, so Swift maps its pointer correctly.
    private var sampler: UnsafeMutablePointer<llama_sampler>?

    private let nCtx: UInt32 = 4096
    private let nBatch: Int32 = 512

    // MARK: Lifecycle

    func load(modelURL: URL) throws {
        Self.configureBackendForPlatform()
        llama_backend_init()

        var mparams = llama_model_default_params()
        #if targetEnvironment(simulator)
        // Simulator Metal is unreliable — keep inference on CPU to avoid ggml aborts.
        mparams.n_gpu_layers = 0
        #endif
        guard let m = llama_model_load_from_file(modelURL.path, mparams) else {
            throw InferenceError.modelLoadFailed
        }
        model = m

        var cparams = llama_context_default_params()
        cparams.n_ctx   = nCtx
        cparams.n_batch = UInt32(nBatch)
        guard let c = llama_init_from_model(m, cparams) else {
            llama_model_free(m)
            throw InferenceError.contextInitFailed
        }
        ctx = c

        // Greedy sampler chain (temperature=0 → deterministic JSON extraction).
        let sparams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        sampler = chain
    }

    /// Platform-specific ggml/Metal workarounds — must run before `llama_backend_init()`.
    private static func configureBackendForPlatform() {
        #if targetEnvironment(simulator)
        // CoreSimulator Metal can assert in ggml residency-set init/decode paths.
        setenv("GGML_METAL_NO_RESIDENCY", "1", 1)
        #endif
    }

    func unload() {
        if let s = sampler { llama_sampler_free(s); sampler = nil }
        if let c = ctx     { llama_free(c);          ctx     = nil }
        if let m = model   { llama_model_free(m);    model   = nil }
        llama_backend_free()
    }

    // MARK: Completion

    func complete(prompt: String, maxNewTokens: Int, temperature: Float) throws -> String {
        guard let model, let ctx, let sampler else { throw InferenceError.notLoaded }

        guard let vocab = llama_model_get_vocab(model) else {
            throw InferenceError.modelLoadFailed
        }

        if let mem = llama_get_memory(ctx) {
            llama_memory_clear(mem, true)
        }

        // ── 1. Tokenise prompt ──────────────────────────────────────────────
        let maxPromptTokens = Int(nCtx) - maxNewTokens
        guard maxPromptTokens > 0 else { throw InferenceError.tokenizationFailed }

        var promptTokenBuffer = [llama_token](repeating: 0, count: maxPromptTokens)
        let nPrompt = llama_tokenize(
            vocab,
            prompt,
            Int32(prompt.utf8.count),
            &promptTokenBuffer,
            Int32(maxPromptTokens),
            true,
            true
        )
        guard nPrompt > 0 else { throw InferenceError.tokenizationFailed }
        let promptTokens = Array(promptTokenBuffer.prefix(Int(nPrompt)))

        // ── 2. Evaluate prompt in chunks (llama_batch_get_one crashes on b9319+) ──
        var batch = llama_batch_init(nBatch, 0, 1)
        defer { llama_batch_free(batch) }

        var pos: Int32 = 0
        var offset = 0
        while offset < promptTokens.count {
            let chunkSize = min(Int(nBatch), promptTokens.count - offset)
            batch.n_tokens = Int32(chunkSize)

            for index in 0..<chunkSize {
                batch.token[index] = promptTokens[offset + index]
                batch.pos[index] = pos + Int32(index)
                batch.n_seq_id[index] = 1
                if let seqIDs = batch.seq_id, let seqID = seqIDs[index] {
                    seqID[0] = 0
                }
                batch.logits[index] = 0
            }

            let isFinalChunk = offset + chunkSize >= promptTokens.count
            if isFinalChunk {
                batch.logits[chunkSize - 1] = 1
            }

            guard llama_decode(ctx, batch) == 0 else {
                throw InferenceError.decodeFailed
            }

            pos += Int32(chunkSize)
            offset += chunkSize
        }

        // ── 3. Sample new tokens ────────────────────────────────────────────
        var result = ""
        var nCur = Int(pos)
        let maxPosition = min(Int(nCtx), nCur + max(1, maxNewTokens))
        var generatedTokens = 0

        while nCur < maxPosition, generatedTokens < maxNewTokens {
            let newToken = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, newToken) { break }

            llama_sampler_accept(sampler, newToken)
            result += tokenToPiece(vocab: vocab, token: newToken)
            generatedTokens += 1

            batch.n_tokens = 1
            batch.token[0] = newToken
            batch.pos[0] = Int32(nCur)
            batch.n_seq_id[0] = 1
            if let seqIDs = batch.seq_id, let seqID = seqIDs[0] {
                seqID[0] = 0
            }
            batch.logits[0] = 1

            guard llama_decode(ctx, batch) == 0 else { break }
            nCur += 1
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Private helpers

    private func tokenToPiece(vocab: OpaquePointer, token: llama_token) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, true)
        guard n > 0 else { return "" }
        return String(bytes: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    }
}

// MARK: - Errors

enum InferenceError: LocalizedError {
    case notLoaded
    case modelLoadFailed
    case contextInitFailed
    case tokenizationFailed
    case decodeFailed
    case noJSONInResponse(String)
    case malformedResponse
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "AI model is not loaded."
        case .modelLoadFailed:
            return "Failed to load the model file — it may be corrupted. Try re-downloading."
        case .contextInitFailed:
            return "Could not initialise inference context. Device may have insufficient RAM."
        case .tokenizationFailed:
            return "Failed to tokenise the prompt."
        case .decodeFailed:
            return "Token decode step failed."
        case .noJSONInResponse(let r):
            return "No JSON in AI response: \(r.prefix(200))"
        case .malformedResponse:
            return "AI response could not be interpreted."
        case .decodingFailed(let e):
            return "JSON decode failed: \(e.localizedDescription)"
        }
    }
}
