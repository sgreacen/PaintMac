#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$ROOT" -c release --product PaintMac
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
APP="$ROOT/dist/Scottware PaintMac.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PaintMac" "$APP/Contents/MacOS/PaintMac"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/ditto "$BIN/PaintMac_PaintMac.bundle" "$APP/Contents/Resources/PaintMac_PaintMac.bundle"
swift "$ROOT/scripts/generate-icon.swift" "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP"
printf '\nBuilt: %s\n' "$APP"
