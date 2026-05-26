# ADR 0006 — Social URL routing: on-device extraction, no backend

**Date:** 2026-05-26  
**Status:** Accepted

## Context

Users share TikTok, Instagram, and YouTube URLs (and video files) to MealKit via the Share Extension. The app must extract recipe text from these before passing it to the local LLM. The options were:

1. **Server-side extraction** (yt-dlp + hosted Whisper) — reliable for all platforms, but introduces server infrastructure costs, contradicts the "zero server cost" goal, and creates a maintenance burden for a solo developer.
2. **On-device extraction** — zero cost, fully private, but platform-dependent and occasionally brittle.

Investigation found that ReciMe (the reference app) uses server-side extraction — their three-tier pipeline runs on their backend. A purely on-device approach cannot match ReciMe's reliability 100% of the time, but covers the majority of real-world cases at zero cost.

## Decision

Implement a `SocialURLRouter` that runs entirely on-device using the following platform-specific strategies:

| Platform | Strategy | Cost |
|---|---|---|
| **YouTube** | YouTube Timedtext API (`/api/timedtext?v=ID&lang=en`) — no key, stable, returns full captions | Free |
| **TikTok** | Parse `__UNIVERSAL_DATA_FOR_REHYDRATION__` JSON from server-rendered page HTML; extract `desc` (caption) and, if caption is < 50 words, download audio-only CDN URL and transcribe via WhisperKit | Free |
| **TikTok (Tier 3)** | Scan description/caption for recipe blog URL → HTML scrape | Free |
| **Instagram URL** | No reliable on-device path; show graceful prompt guiding user to save video to Photos and share the file to MealKit | Free |
| **Video file (any source)** | WhisperKit on-device transcription | Free |
| **Recipe blogs** | HTML scraping (existing `fetchRecipeText`) | Free |

The TikTok rehydration JSON approach is best-effort: TikTok occasionally changes JSON key paths or rate-limits non-browser User-Agents. Multiple JSON path fallbacks are implemented to improve resilience.

## Consequences

**Positive**
- Zero infrastructure cost, fully on-device, no API keys required.
- YouTube support is robust (stable undocumented API that many apps rely on).
- TikTok caption extraction works for the majority of food creator posts (captions usually contain full recipes).
- WhisperKit transcription works for all video files regardless of source.

**Negative**
- TikTok JSON parsing is brittle — TikTok can break it unilaterally at any time.
- Instagram URL import is unsupported (only video file path works for Instagram).
- YouTube videos without auto-generated captions fall through to "no text found."

**Neutral**
- ReciMe parity is achieved for YouTube and the common TikTok case. Full parity on Instagram requires the video-file path.

## Alternatives considered

- **Hosted yt-dlp on Fly.io free tier** — rejected because even free-tier hosting has maintenance cost, network dependency, and is not truly zero-cost long-term.
- **Instagram oEmbed** — accessible without auth as of May 2026 but returns embed HTML not caption text, and ToS prohibits extraction use.
