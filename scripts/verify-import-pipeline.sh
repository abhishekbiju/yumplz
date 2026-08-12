#!/usr/bin/env bash
# End-to-end import pipeline verification for yumplz.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIM="${SIM_DEVICE:-iPhone 17}"
DEST="platform=iOS Simulator,name=${SIM}"

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Unit tests (mocked social import)"
xcodebuild test \
  -scheme Yumplz \
  -destination "$DEST" \
  -only-testing:YumplzTests/LiveImportPipelineTests \
  -only-testing:YumplzTests/SocialURLRouterIntegrationTests \
  -only-testing:YumplzTests/TikTokImportPipelineTests \
  -only-testing:YumplzTests/ShareImportPipelineIntegrationTests \
  -only-testing:YumplzTests/RecipeImportQualityTests \
  -only-testing:YumplzTests/RecipeJSONParserTests \
  -quiet

echo "==> Live network extraction (YouTube Shorts, YouTube long-form, TikTok caption)"
# NOTE: xcodebuild does not forward plain env vars into the simulator's test
# process — only vars prefixed TEST_RUNNER_ are passed through (prefix stripped
# on the other side). Without the prefix these tests silently report "skipped"
# and the whole live-network check gives false confidence.
TEST_RUNNER_YUMPLZ_LIVE_PIPELINE=1 xcodebuild test \
  -scheme Yumplz \
  -destination "$DEST" \
  -only-testing:YumplzTests/LiveImportPipelineTests/testLiveDemoYouTubeShort_extractsRecipeTextFromNetwork \
  -only-testing:YumplzTests/LiveImportPipelineTests/testLiveYouTubeLongForm_extractsRecipeTextFromNetwork \
  -only-testing:YumplzTests/LiveImportPipelineTests/testLiveTikTokCaptionRecipe_extractsRecipeTextFromNetwork \
  -quiet

if [[ "${YUMPLZ_LIVE_LLM:-0}" == "1" ]]; then
  echo "==> Live LLM parse (requires downloaded model)"
  TEST_RUNNER_YUMPLZ_LIVE_LLM=1 xcodebuild test \
    -scheme Yumplz \
    -destination "$DEST" \
    -only-testing:YumplzTests/RecipeJSONParserTests \
    -quiet
fi

echo "==> All import pipeline checks passed"
