#!/bin/sh
set -eu

VERSION="${1:-0.1.2}"
OUTPUT_DIR="${2:-dist}"
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
STAGE_DIR="$PROJECT_DIR/.build/package-stage"
APP_DIR="$STAGE_DIR/Agent Fanny Pack.app"
ARM_SCRATCH="$PROJECT_DIR/.build/release-arm64"
INTEL_SCRATCH="$PROJECT_DIR/.build/release-x86_64"

case "$VERSION" in
  *[!0-9.]*|'') echo "Version must contain digits and dots only" >&2; exit 2 ;;
esac

case "$STAGE_DIR" in
  "$PROJECT_DIR"/.build/package-stage) ;;
  *) echo "Refusing unexpected staging path" >&2; exit 2 ;;
esac
test -n "$PROJECT_DIR"
test -d "$PROJECT_DIR"

cd "$PROJECT_DIR"
swift build --disable-sandbox -c release --product AgentFannyPack --triple arm64-apple-macosx13.0 --scratch-path "$ARM_SCRATCH"
swift build --disable-sandbox -c release --product AgentFannyPack --triple x86_64-apple-macosx13.0 --scratch-path "$INTEL_SCRATCH"

ARM_BIN="$ARM_SCRATCH/arm64-apple-macosx/release/AgentFannyPack"
INTEL_BIN="$INTEL_SCRATCH/x86_64-apple-macosx/release/AgentFannyPack"
test -x "$ARM_BIN"
test -x "$INTEL_BIN"

if test -e "$STAGE_DIR"; then
  test ! -L "$STAGE_DIR"
  rm -rf "$STAGE_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$OUTPUT_DIR"
lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP_DIR/Contents/MacOS/AgentFannyPack"
chmod 755 "$APP_DIR/Contents/MacOS/AgentFannyPack"
ln -s AgentFannyPack "$APP_DIR/Contents/MacOS/agent-fanny-pack"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"

xcrun swiftc -parse-as-library tools/IconMaker.swift -framework AppKit -o "$STAGE_DIR/icon-maker"
"$STAGE_DIR/icon-maker" "$STAGE_DIR/icon-1024.png"
ICONSET="$STAGE_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16 "$STAGE_DIR/icon-1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$STAGE_DIR/icon-1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$STAGE_DIR/icon-1024.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$STAGE_DIR/icon-1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$STAGE_DIR/icon-1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$STAGE_DIR/icon-1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$STAGE_DIR/icon-1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$STAGE_DIR/icon-1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$STAGE_DIR/icon-1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$STAGE_DIR/icon-1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
file "$APP_DIR/Contents/MacOS/AgentFannyPack" | grep -q 'universal binary'

ARCHIVE_NAME="Agent-Fanny-Pack-$VERSION.zip"
ARCHIVE="$PROJECT_DIR/$OUTPUT_DIR/$ARCHIVE_NAME"
CHECKSUM="$ARCHIVE.sha256"
rm -f "$ARCHIVE" "$CHECKSUM"
find "$APP_DIR" -exec touch -h -t 202601010000 {} +
(
  cd "$STAGE_DIR"
  find "Agent Fanny Pack.app" -print | LC_ALL=C sort | zip -X -y "$ARCHIVE" -@ >/dev/null
)
(
  cd "$(dirname "$ARCHIVE")"
  shasum -a 256 "$ARCHIVE_NAME"
) > "$CHECKSUM"
printf '%s\n' "$ARCHIVE"
cat "$CHECKSUM"
