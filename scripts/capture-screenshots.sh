#!/usr/bin/env bash
# Captures README screenshots from the iOS Simulator (DEBUG build only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -z "${SIM_DEVICE:-}" ]; then
  SIM_DEVICE="iPhone 17"
fi
DERIVED="${DERIVED:-/tmp/yumplz-screenshot-derived}"
OUT="$ROOT/docs/screenshots"
BUNDLE="com.abhishekbiju.yumplz"

echo "Generating Xcode project..."
xcodegen generate

echo "Building yumplz for ${SIM_DEVICE}..."
xcodebuild \
  -scheme Yumplz \
  -destination "platform=iOS Simulator,name=${SIM_DEVICE}" \
  -derivedDataPath "$DERIVED" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Yumplz.app"
mkdir -p "$OUT"

echo "Preparing simulator..."
xcrun simctl boot "$SIM_DEVICE" 2>/dev/null || true
xcrun simctl bootstatus booted -b
xcrun simctl uninstall booted "$BUNDLE" 2>/dev/null || true
xcrun simctl install booted "$APP"

capture() {
  local file="$1"
  local tab="$2"
  echo "Capturing ${file} (tab=${tab})..."
  xcrun simctl terminate booted "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_YUMPLZ_SCREENSHOT_MODE=1 \
  SIMCTL_CHILD_YUMPLZ_SCREENSHOT_TAB="$tab" \
    xcrun simctl launch booted "$BUNDLE" >/dev/null
  sleep 6
  xcrun simctl io booted screenshot "$OUT/$file"
}

capture "discover.png" "discover"
capture "library.png" "library"
capture "plan.png" "plan"
capture "grocery.png" "grocery"
capture "profile.png" "profile"

echo "Screenshots saved to ${OUT}"
