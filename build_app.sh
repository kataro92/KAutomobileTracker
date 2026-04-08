#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

ARCH="$(uname -m)"
swift build -c release --arch "$ARCH"

APP="$ROOT/KAutomobileTracker.app"
BIN="$ROOT/.build/${ARCH}-apple-macosx/release/KAutomobileTracker"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/.build/release/KAutomobileTracker"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KAutomobileTracker"
cp "$ROOT/Sources/KAutomobileTracker/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "Built $APP"
