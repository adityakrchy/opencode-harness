#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"

echo "Building OpenCode Harness (Release)…"
xcodebuild \
  -project "$ROOT/OpenCodeHarness.xcodeproj" \
  -scheme OpenCodeHarness \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

APP="$DERIVED/Build/Products/Release/OpenCode Harness.app"
if [[ ! -d "$APP" ]]; then
  echo "Build finished but the app was not found at $APP" >&2
  exit 1
fi

rm -rf "$ROOT/dist"
mkdir -p "$ROOT/dist"
ditto "$APP" "$ROOT/dist/OpenCode Harness.app"
echo "Built: $ROOT/dist/OpenCode Harness.app"
echo "Run:   open \"$ROOT/dist/OpenCode Harness.app\""
