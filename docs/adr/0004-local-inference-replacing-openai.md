# ADR 0004 — On-device inference (llama.cpp + WhisperKit) replacing OpenAI

- Status: Accepted
- Date: 2026-05-25
- Supersedes (in part): ADR 0001 (eliminates the Cloudflare Worker proxy)

## Context

ADR 0001 described a thin Cloudflare Worker that proxied recipe-import calls to
OpenAI `gpt-4o-mini` and OpenAI Whisper. That proxy was the only backend
infrastructure the app operated. The original decision accepted that dependency
in exchange for parsing quality.

The project now requires that **all inference run entirely on the user's device**,
with no external API calls for parsing, normalisation, or transcription. The
motivations are:

- No API key exposure or per-call cost at any user scale.
- Fully offline operation after model download: the app imports, plans, and
  generates grocery lists with no network dependency.
- Competitive differentiation: "AI features that work on a plane."
- Removal of the only server-side component we operated, eliminating the
  corresponding ops surface.

The tasks that need inference are bounded and short-context:

| Task | Input | Output |
|---|---|---|
| Recipe field extraction | Fetched URL HTML / pasted text / OCR text | JSON recipe schema |
| Ingredient structured parse | One ingredient line | `{qty, unit, name, prep}` |
| Timer duration detection | One step string | Seconds or null |
| Store category assignment | Ingredient name | One of 9 fixed labels |
| Nutrition estimation | Recipe title + ingredient list | `{cal, protein, carbs, fat}` |
| Plan generation | User constraints + recipe list | Ordered slot → recipe assignments |
| Video transcription | Audio extracted from social video URL | Transcript text |

All but the last are structured-extraction tasks with short context windows.
None require the open-ended reasoning that justifies a large model.

## Decision

### LLM runtime: llama.cpp with CoreML/Metal backend

We will use **`llama.cpp`** (via its Swift Package Manager interface) as the
inference runtime for all text-generation tasks. Model files are in **GGUF
format**, which llama.cpp loads natively.

Target model: **Llama 3.2 3B (Q4_K_M quantisation)** — approximately 2.0 GB
on disk, approximately 2.5 GB RAM at inference. This fits within the memory
budget of every iPhone from iPhone 14 onward.

The llama.cpp CoreML backend compiles the model's attention layers into a
`.mlmodelc` package at first load, offloading them to the Neural Engine. This
cuts per-token latency on A-series chips by roughly 2–3×. The compiled cache
persists across launches so the compilation cost is paid once.

8B-class models were considered and rejected:
- 4-bit Q4 of Llama 3.1 8B is ~4.5 GB on disk, ~5.5 GB RAM — exceeds memory
  headroom on all 6 GB iPhones (iPhone 14 line and below), roughly half the
  addressable market.
- Inference at 5–10 tok/s produces a perceivable wait on import; 3B at
  15–25 tok/s is acceptable.
- The quality delta for our structured-extraction workload is negligible: a
  3B model with a tight JSON schema prompt reliably outperforms a 8B model
  without one.

### Transcription: WhisperKit

We will use **WhisperKit** (by Argmax) for audio transcription from social
video imports. WhisperKit is a CoreML port of OpenAI's Whisper, distributed as
a Swift Package. Target model: **`whisper-base.en`** (~150 MB). It runs
entirely on-device via the Neural Engine, with no length cap and no network
dependency.

Apple's `SFSpeechRecognizer` was considered and rejected: it degrades on
cooking-video audio (background music, overlapping speech, non-native accents)
and imposes a hard ~60-second limit per request, which eliminates most real
cooking videos.

### Model delivery: deferred on-demand download

Neither model is bundled with the app binary.

- The LLM (~2.0 GB) is downloaded the first time the user triggers an Import
  that requires inference (URL parse, photo OCR parse, paste, or video).
- The Whisper model (~150 MB) is downloaded the first time the user imports
  from a video URL.
- Downloads are managed by `URLSession` background tasks, surfaced in the app
  as a progress sheet before the first inference call proceeds.
- After download, models are stored in `Application Support` (excluded from
  iCloud backup via `isExcludedFromBackup = true`). They survive app updates
  and are only re-downloaded if the user manually deletes them via Settings.

### Plan Generation: decomposed multi-step prompting

Plan Generation stays as described in CONTEXT.md (an LLM-powered, user-
reviewed draft of a week's meals) but now runs locally on the 3B model.

Because a single "plan my whole week" prompt strains a 3B context window, the
generation is decomposed into a chain of smaller calls:

1. **Slot enumeration**: list all (date, slot) pairs for the requested range.
2. **Constraint resolution**: for each slot, determine applicable filters
   (dietary, cuisine preference, time budget) from user settings.
3. **Candidate selection**: for each slot, ask the model to pick one recipe
   from a short candidate list (fed in JSON) that best satisfies the
   constraints — a classification/ranking task, not free-form generation.
4. **Variety check**: pass the full draft plan back for a single review call
   that identifies obvious repetition (same protein two days in a row, etc.)
   and swaps candidates where needed.

This decomposition keeps each call's context window under ~2 k tokens, which
3B models handle reliably. Quality is "good draft, user reviews" — the same
expectation set by the prior API-backed design.

Plan Generation remains a paywalled paid feature for App Store release. For
the TestFlight beta all features are unlocked so testers can exercise the
full flow and provide quality signal.

### NLP search removed

The "Ask AI" natural language search escape hatch (previously an OpenAI call)
is removed entirely. Search is SQLite FTS5 only. This is a product
simplification, not a quality degradation — the use cases it served
(semantic queries like "something quick with chicken") are well-covered by
FTS5 with dietary-tag and time filters.

## Consequences

### Positive

- Zero external API dependency for core app features after model download.
- App works fully offline.
- No API keys in the binary or on a proxy server.
- Cloudflare Worker eliminated — zero server infrastructure.
- Per-user cost is now zero beyond Apple's CloudKit free tier.

### Negative — accepted trade-offs

- **2.15 GB download before first Import.** Users on cellular or slow Wi-Fi
  face a meaningful wait. Mitigated by: surfacing the download as an explicit
  step with progress and an estimated time, and by triggering it lazily (only
  when the user actually tries to import).
- **Minimum device constraint.** The 3B model requires ~2.5 GB RAM headroom.
  We will add a runtime check and surface a "device not supported" message on
  devices with insufficient memory (practically: iPhone X and older with 3 GB
  RAM).
- **Plan Generation quality lower than GPT-4o.** A 3B model with decomposed
  prompting produces sensible first drafts but may occasionally violate
  soft constraints. The UI must set expectations: "AI suggestion — review
  before adding to plan."
- **First-inference latency.** The CoreML model compilation at first load takes
  30–90 seconds on first launch after download. Subsequent launches use the
  compiled cache and start in under 2 seconds.

### Reversal cost

Low for the Whisper swap (WhisperKit is a drop-in API shim). Moderate for the
LLM: replacing llama.cpp with an API call is a service-layer change, not a
model change — the prompt templates and JSON schemas are reusable.

## Alternatives considered

- **Apple Foundation Models framework (iOS 18 on-device LLM).** The private
  system model is gated behind Apple's task-specific APIs (writing tools,
  summarisation). There is no general-purpose token generation API available
  to third-party apps as of iOS 18.4. Rejected: insufficient API surface.
- **MLX Swift.** Apple's ML compute framework for Apple Silicon. Well-suited
  for Mac but iOS support and Llama 3 GGUF loading are less mature than
  llama.cpp as of this writing. Revisit if the ecosystem matures.
- **Retain OpenAI for Plan Generation only.** Keeping one API call for the
  highest-value task while moving parsing local was considered. Rejected:
  the user explicitly requires all inference to be local; the decomposed
  prompting approach makes the quality trade-off acceptable.
