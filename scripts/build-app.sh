#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/AgentHighlight.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
swift build -c release >&2

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/.build/release/AgentHighlightApp" "$CONTENTS/MacOS/AgentHighlight"
printf 'APPL????' > "$CONTENTS/PkgInfo"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)"
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
fi
codesign --force --deep --sign "$IDENTITY" "$APP" >&2
echo "signed with: $IDENTITY" >&2

echo "$APP"
