#!/bin/sh
set -eu

VERSION="${1:-0.1.2}"
OUTPUT_DIR="${2:-dist}"
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ARCHIVE_NAME="Agent-Fanny-Pack-$VERSION-source.tar.gz"
ARCHIVE="$PROJECT_DIR/$OUTPUT_DIR/$ARCHIVE_NAME"
CHECKSUM="$ARCHIVE.sha256"

case "$VERSION" in
  *[!0-9.]*|'') echo "Version must contain digits and dots only" >&2; exit 2 ;;
esac

cd "$PROJECT_DIR"
test "$(git rev-parse "v$VERSION^{commit}")" = "$(git rev-parse HEAD)"
mkdir -p "$OUTPUT_DIR"
rm -f "$ARCHIVE" "$CHECKSUM"
git archive --format=tar --prefix="agent-fanny-pack-$VERSION/" "v$VERSION" | gzip -n -9 > "$ARCHIVE"
(
  cd "$(dirname "$ARCHIVE")"
  shasum -a 256 "$ARCHIVE_NAME"
) > "$CHECKSUM"

printf '%s\n' "$ARCHIVE"
cat "$CHECKSUM"
