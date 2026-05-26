import Foundation
import LlamaSwift   // @_exported @preconcurrency import llama — raw llama.cpp C API (b9319+)
import os.log

private let log = Logger(subsystem: "com.abhishekbiju.mealkit", category: "Inference")

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

    func parseRecipe(from text: String) async throws -> ParsedRecipeDTO {
        let raw = try await complete(prompt: RecipePrompts.recipeExtractionPrompt(from: text))
        return try decodeDTO(ParsedRecipeDTO.self, from: raw)
    }

    // MARK: Private

    private func llamaChatPrompt(system: String, user: String) -> String {
        "<|begin_of_text|>" +
        "<|start_header_id|>system<|end_header_id|>\n\(system)<|eot_id|>" +
        "<|start_header_id|>user<|end_header_id|>\n\(user)<|eot_id|>" +
        "<|start_header_id|>assistant<|end_header_id|>\n"
    }

    private func decodeDTO<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        guard let jsonString = raw.extractedJSON() else {
            throw InferenceError.noJSONInResponse(raw)
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw InferenceError.malformedResponse
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            log.error("Decode failed: \(error.localizedDescription, privacy: .public)")
            throw InferenceError.decodingFailed(error)
        }
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

    // MARK: Lifecycle

    func load(modelURL: URL) throws {
        llama_backend_init()

        var mparams = llama_model_default_params()
        guard let m = llama_model_load_from_file(modelURL.path, mparams) else {
            throw InferenceError.modelLoadFailed
        }
        model = m

        var cparams = llama_context_default_params()
        cparams.n_ctx   = nCtx
        cparams.n_batch = 512
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

    func unload() {
        if let s = sampler { llama_sampler_free(s); sampler = nil }
        if let c = ctx     { llama_free(c);          ctx     = nil }
        if let m = model   { llama_model_free(m);    model   = nil }
        llama_backend_free()
    }

    // MARK: Completion

    func complete(prompt: String, maxNewTokens: Int, temperature: Float) throws -> String {
        guard let model, let ctx, let sampler else { throw InferenceError.notLoaded }

        // Get the vocab (needed for tokenise / detokenise / EOS check).
        guard let vocab = llama_model_get_vocab(model) else {
            throw InferenceError.modelLoadFailed
        }

        // Clear KV cache between calls (replaces removed llama_kv_cache_clear).
        if let mem = llama_get_memory(ctx) {
            llama_memory_clear(mem, true)
        }

        // ── 1. Tokenise prompt ──────────────────────────────────────────────
        let maxPromptTokens = Int(nCtx) - maxNewTokens
        var promptTokens = [llama_token](repeating: 0, count: maxPromptTokens)
        let nPrompt = llama_tokenize(
            vocab,
            prompt,
            Int32(prompt.utf8.count),
            &promptTokens,
            Int32(maxPromptTokens),
            true,   // add_special (BOS)
            true    // parse_special (<|...|> tokens)
        )
        guard nPrompt > 0 else { throw InferenceError.tokenizationFailed }

        // ── 2. Feed prompt as a single batch ────────────────────────────────
        let promptDecodeResult = promptTokens.withUnsafeMutableBufferPointer { buf -> Int32 in
            let batch = llama_batch_get_one(buf.baseAddress!, nPrompt)
            return llama_decode(ctx, batch)
        }
        guard promptDecodeResult == 0 else { throw InferenceError.decodeFailed }

        // ── 3. Sample new tokens ────────────────────────────────────────────
        var result = ""
        var nCur = Int(nPrompt)

        while nCur < Int(nCtx) {
            let newToken = llama_sampler_sample(sampler, ctx, -1)

            // `llama_vocab_is_eog` catches EOS, EOT, and any other
            // end-of-generation tokens (cleaner than comparing to eos only).
            if llama_vocab_is_eog(vocab, newToken) { break }

            llama_sampler_accept(sampler, newToken)

            let piece = tokenToPiece(vocab: vocab, token: newToken)
            result += piece

            // Feed the new token back for the next decode step.
            var tokenForBatch = newToken
            let nextDecodeResult = withUnsafeMutablePointer(to: &tokenForBatch) { ptr -> Int32 in
                let batch = llama_batch_get_one(ptr, 1)
                return llama_decode(ctx, batch)
            }
            guard nextDecodeResult == 0 else { break }

            nCur += 1

            // Bail early if we've clearly overshot the requested output length.
            if result.count > maxNewTokens * 6 { break }
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
