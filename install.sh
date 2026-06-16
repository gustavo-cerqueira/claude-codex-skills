#!/usr/bin/env bash
# install.sh — install the claude-codex-skills into a target project.
#
# Installs two skills (claude-codex-plan, codex-gate) plus the gate enforcement
# hook so they are discoverable by Claude Code and/or OpenAI Codex.
#
# Usage:
#   ./install.sh [--target <project-dir>] [--mode claude|codex|both] [--copy]
#
#   --target <dir>   Project to install into (default: current directory).
#   --mode <m>       claude | codex | both   (default: both).
#   --copy           Copy files instead of symlinking (self-contained install).
#                    Default is symlink, so `git pull` in this repo updates the
#                    installed skills automatically.
#
# Claude Code  -> skills land in  <target>/.claude/skills/<name>
#                 hook lands in   <target>/.claude/hooks/gate-enforce.py
#                 (prints the settings.json snippet to register the hook)
# Codex        -> ensures         <target>/.agents -> .claude   symlink, so Codex
#                 discovers the same skills via .agents/skills/.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$PWD"
MODE="both"
LINK=1
SKILLS=(claude-codex-plan codex-gate)

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --mode)   MODE="$2";   shift 2 ;;
    --copy)   LINK=0;      shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

TARGET="$(cd "$TARGET" && pwd)"
[ -d "$TARGET" ] || { echo "install.sh: target not found: $TARGET" >&2; exit 2; }
case "$MODE" in claude|codex|both) ;; *) echo "install.sh: --mode must be claude|codex|both" >&2; exit 2 ;; esac

place() {  # place <src> <dest>
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  if [ "$LINK" -eq 1 ]; then ln -s "$src" "$dest"; else cp -R "$src" "$dest"; fi
}

install_claude() {
  local skills_root="$TARGET/.claude/skills" hooks_root="$TARGET/.claude/hooks"
  for s in "${SKILLS[@]}"; do
    place "$SRC_DIR/skills/$s" "$skills_root/$s"
    echo "  • skill: .claude/skills/$s"
  done
  place "$SRC_DIR/hooks/gate-enforce.py" "$hooks_root/gate-enforce.py"
  chmod +x "$hooks_root/gate-enforce.py" 2>/dev/null || true
  echo "  • hook:  .claude/hooks/gate-enforce.py"
  cat <<'SNIPPET'

  → Register the enforcement hook in <target>/.claude/settings.json:

    {
      "hooks": {
        "PostToolUse": [
          {
            "matcher": "Edit|Write|MultiEdit",
            "hooks": [
              { "type": "command",
                "command": "python3 \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/gate-enforce.py" }
            ]
          }
        ]
      }
    }
SNIPPET
}

install_codex() {
  local agents="$TARGET/.agents"
  if [ -e "$agents" ] && [ ! -L "$agents" ]; then
    echo "  ! $TARGET/.agents exists and is not a symlink — leaving it untouched." >&2
    echo "    Codex must be able to read the skills under .agents/skills/." >&2
  else
    rm -f "$agents"
    ( cd "$TARGET" && ln -s .claude .agents )
    echo "  • codex: .agents -> .claude  (Codex discovers skills via .agents/skills/)"
  fi
  echo "    For deterministic enforcement under Codex, install the git pre-commit hook:"
  echo "      cp \"$SRC_DIR/hooks/pre-commit\" \"$TARGET/.git/hooks/pre-commit\" && chmod +x \"$TARGET/.git/hooks/pre-commit\""
}

echo "Installing claude-codex-skills into: $TARGET   (mode=$MODE, $([ "$LINK" -eq 1 ] && echo symlink || echo copy))"
case "$MODE" in
  claude) install_claude ;;
  codex)  install_codex ;;
  both)   install_claude; echo; install_codex ;;
esac
echo
echo "Done. Requirement: both 'claude' and 'codex' CLIs on PATH and signed in."
