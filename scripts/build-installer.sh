#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/build-app.sh"
APP="$ROOT/dist/Scottware PaintMac.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/PaintMac")"
case "$ARCH" in
    arm64) PLATFORM="Apple-Silicon" ;;
    x86_64) PLATFORM="Intel" ;;
    *) PLATFORM="Universal" ;;
esac
NAME="Scottware-PaintMac-${VERSION}-${PLATFORM}"
DMG="$ROOT/dist/$NAME.dmg"
WORK="$(mktemp -d "$ROOT/dist/.installer-XXXXXX")"
MOUNT="$WORK/mount"
MOUNTED=false
cleanup() {
    if [ "$MOUNTED" = true ]; then
        /usr/bin/hdiutil detach "$MOUNT" -quiet || true
    fi
    /bin/rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/payload" "$MOUNT"
/usr/bin/ditto "$APP" "$WORK/payload/Scottware PaintMac.app"
/bin/ln -s /Applications "$WORK/payload/Applications"
/bin/cp "$ROOT/Resources/Install.rtf" "$WORK/payload/Install Scottware PaintMac.rtf"
/usr/bin/codesign --verify --strict "$WORK/payload/Scottware PaintMac.app"

/usr/bin/hdiutil create -volname "Scottware PaintMac" \
    -srcfolder "$WORK/payload" -fs HFS+ -format UDZO -imagekey zlib-level=9 \
    "$WORK/$NAME.dmg"
/usr/bin/hdiutil verify "$WORK/$NAME.dmg"
/usr/bin/hdiutil attach "$WORK/$NAME.dmg" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT"
MOUNTED=true
/usr/bin/codesign --verify --strict --verbose=2 "$MOUNT/Scottware PaintMac.app"
/usr/bin/cmp "$APP/Contents/MacOS/PaintMac" "$MOUNT/Scottware PaintMac.app/Contents/MacOS/PaintMac"
/usr/bin/cmp "$APP/Contents/Info.plist" "$MOUNT/Scottware PaintMac.app/Contents/Info.plist"
test "$(/usr/bin/readlink "$MOUNT/Applications")" = "/Applications"
test -f "$MOUNT/Install Scottware PaintMac.rtf"
/usr/bin/hdiutil detach "$MOUNT" -quiet
MOUNTED=false
/bin/mv -f "$WORK/$NAME.dmg" "$DMG"
/usr/bin/shasum -a 256 "$DMG" > "$DMG.sha256"
printf '\nInstaller: %s\nChecksum:  %s\nArchitecture: %s\n' "$DMG" "$DMG.sha256" "$ARCH"
