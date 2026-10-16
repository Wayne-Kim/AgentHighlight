#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="$("$ROOT/scripts/build-app.sh")"
APP_TARGET="$HOME/Applications/AgentHighlight.app"

if pgrep -x AgentHighlight >/dev/null 2>&1; then
  osascript -e 'quit app "AgentHighlight"' >/dev/null 2>&1 || true
  sleep 1
fi

mkdir -p "$HOME/Applications"
rm -rf "$APP_TARGET"
cp -R "$APP_SOURCE" "$APP_TARGET"

if [ -w /usr/local/bin ]; then
  BIN_DIR=/usr/local/bin
else
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
fi
cp "$ROOT/.build/release/hl" "$BIN_DIR/hl"
chmod +x "$BIN_DIR/hl"

open -a "$APP_TARGET"
sleep 1.5

echo "app: $APP_TARGET"
echo "hl:  $BIN_DIR/hl"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "PATH 에 $BIN_DIR 이 없습니다. 셸 설정에 추가하세요: export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
"$BIN_DIR/hl" doctor || true
