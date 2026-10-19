#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="$("$ROOT/scripts/build-app.sh")"
APP_TARGET="$HOME/Applications/AgentHighlight.app"

pkill -x AgentHighlightApp 2>/dev/null || true
if pgrep -x AgentHighlight >/dev/null 2>&1; then
  osascript -e 'quit app "AgentHighlight"' >/dev/null 2>&1 || true
fi
for _ in $(seq 1 20); do
  if ! pgrep -x AgentHighlight >/dev/null 2>&1 && ! pgrep -x AgentHighlightApp >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

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

SHARED_SKILL="$HOME/.agents/skills/agent-highlight"
mkdir -p "$HOME/.agents/skills"
ln -sfn "$ROOT/skills/agent-highlight" "$SHARED_SKILL"
echo "skill: $SHARED_SKILL -> $ROOT/skills/agent-highlight"
for AGENT_SKILLS in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.factory/skills" "$HOME/.copilot/skills" "$HOME/.config/opencode/skills" "$HOME/.cursor/skills" "$HOME/.gemini/skills"; do
  AGENT_HOME="$(dirname "$AGENT_SKILLS")"
  [ -d "$AGENT_HOME" ] || continue
  mkdir -p "$AGENT_SKILLS"
  ln -sfn "$SHARED_SKILL" "$AGENT_SKILLS/agent-highlight"
  echo "skill: $AGENT_SKILLS/agent-highlight"
done

if [ -d "$HOME/.codex" ]; then
  mkdir -p "$HOME/.codex/rules"
  cat > "$HOME/.codex/rules/agent-highlight.rules" <<RULES
prefix_rule(pattern = ["hl"], decision = "allow")
prefix_rule(pattern = ["$BIN_DIR/hl"], decision = "allow")
RULES
  echo "codex rule: $HOME/.codex/rules/agent-highlight.rules"
fi

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ]; then
  python3 -I - "$CLAUDE_SETTINGS" "$BIN_DIR/hl" <<'PY'
import json, sys
path, binary = sys.argv[1], sys.argv[2]
with open(path) as f:
    settings = json.load(f)
allow = settings.setdefault("permissions", {}).setdefault("allow", [])
for rule in ["Bash(hl:*)", f"Bash({binary}:*)"]:
    if rule not in allow:
        allow.append(rule)
with open(path, "w") as f:
    json.dump(settings, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
  echo "claude allow: Bash(hl:*)"
fi

open -a "$APP_TARGET"
sleep 1.5

echo "app: $APP_TARGET"
echo "hl:  $BIN_DIR/hl"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "PATH 에 $BIN_DIR 이 없습니다. 셸 설정에 추가하세요: export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
"$BIN_DIR/hl" doctor || true
