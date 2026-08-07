#!/bin/sh
set -eu

PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIR"

FILES="$(find . -type f \
  -not -path './.git/*' \
  -not -path './.build*/*' \
  -not -path './dist/*' \
  -not -path './work/*' \
  -not -path './outputs/*' \
  -not -path './.swiftpm/*' | LC_ALL=C sort)"

test -n "$FILES"

PATH_SCAN_FILES="$(printf '%s\n' "$FILES" | grep -v '^./scripts/public_safety_scan.sh$')"
if printf '%s\n' "$PATH_SCAN_FILES" | xargs grep -IEn '/Users/[^/]+|Documents/Codex|file:///' >/tmp/agent-fanny-pack-path-scan.txt 2>/dev/null; then
  cat /tmp/agent-fanny-pack-path-scan.txt >&2
  echo "Public-safety scan found a local path" >&2
  exit 1
fi

if printf '%s\n' "$FILES" | xargs grep -IEn '(gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{12,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]{8,})' >/tmp/agent-fanny-pack-secret-scan.txt 2>/dev/null; then
  cat /tmp/agent-fanny-pack-secret-scan.txt >&2
  echo "Secret scan found a credential-shaped value" >&2
  exit 1
fi

if printf '%s\n' "$FILES" | xargs grep -IEn '[[:alnum:]._%+-]+@(gmail|outlook|yahoo|icloud|protonmail)\.[[:alpha:]]{2,}' >/tmp/agent-fanny-pack-email-scan.txt 2>/dev/null; then
  cat /tmp/agent-fanny-pack-email-scan.txt >&2
  echo "Public-safety scan found a personal email" >&2
  exit 1
fi

swift package dump-package >/tmp/agent-fanny-pack-package.json
if grep -Eq '"dependencies"[[:space:]]*:[[:space:]]*\[[^]]' /tmp/agent-fanny-pack-package.json; then
  echo "Unexpected external Swift dependency" >&2
  exit 1
fi

echo "Public-safety scan passed: $(printf '%s\n' "$FILES" | wc -l | tr -d ' ') files; no local paths, personal email, credential-shaped value, or external Swift dependency."
