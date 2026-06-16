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
# Skills always land under  <target>/.claude/skills/<name>  and the hook under
# <target>/.claude/hooks/gate-enforce.py. Codex discovers them through a
# <target>/.agents -> .claude symlink. Claude mode prints the settings.json
# snippet; codex mode installs a git pre-commit hook (if .git is present and no
# pre-commit hook already exists).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$PWD"
MODE="both"
LINK=1
SKILLS=(claude-codex-plan codex-gate)

req() { [ "$1" -ge 2 ] || { echo "install.sh: $2 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target) req $# "$1"; TARGET="$2"; shift 2 ;;
    --mode)   req $# "$1"; MODE="$2";   shift 2 ;;
    --copy)   LINK=0; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -d "$TARGET" ] || { echo "install.sh: target not found: $TARGET" >&2; exit 2; }
TARGET="$(cd "$TARGET" && pwd)"
case "$MODE" in claude|codex|both) ;; *) echo "install.sh: --mode must be claude|codex|both" >&2; exit 2 ;; esac

place() {  # place <src> <dest>
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  if [ "$LINK" -eq 1 ]; then ln -s "$src" "$dest"; else cp -R "$src" "$dest"; fi
}

install_skills() {
  local skills_root="$TARGET/.claude/skills"
  for s in "${SKILLS[@]}"; do
    place "$SRC_DIR/skills/$s" "$skills_root/$s"
    echo "  • skill: .claude/skills/$s"
  done
}

install_hook_file() {
  place "$SRC_DIR/hooks/gate-enforce.py" "$TARGET/.claude/hooks/gate-enforce.py"
  chmod +x "$TARGET/.claude/hooks/gate-enforce.py" 2>/dev/null || true
  echo "  • hook:  .claude/hooks/gate-enforce.py"
}

claude_extras() {
  cat <<'SNIPPET'

  → Register the enforcement hook in <target>/.claude/settings.json
    (append to an existing PostToolUse array rather than replacing the file):

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

    NOTE: the PostToolUse hook only fires for Edit/Write/MultiEdit. A PROGRESS.md
    edited via Bash bypasses it — the git pre-commit hook (codex mode) is the
    authoritative, CLI-agnostic backstop.
SNIPPET
}

codex_extras() {
  local agents="$TARGET/.agents"
  if [ -e "$agents" ] && [ ! -L "$agents" ]; then
    echo "  ! $TARGET/.agents exists and is not a symlink — leaving it untouched." >&2
    echo "    Codex must read skills under .agents/skills/ (point it at .claude)." >&2
  else
    rm -f "$agents"
    ( cd "$TARGET" && ln -s .claude .agents )
    echo "  • codex: .agents -> .claude  (Codex discovers skills via .agents/skills/)"
  fi

  local ghooks="$TARGET/.git/hooks"
  if [ -d "$TARGET/.git" ]; then
    if [ -e "$ghooks/pre-commit" ]; then
      echo "  ! .git/hooks/pre-commit already exists — not overwriting. To enable the gate,"
      echo "    merge in: python3 \"$TARGET/.claude/hooks/gate-enforce.py\" (see hooks/pre-commit)."
    else
      mkdir -p "$ghooks"
      cp "$SRC_DIR/hooks/pre-commit" "$ghooks/pre-commit"
      chmod +x "$ghooks/pre-commit"
      echo "  • git:   .git/hooks/pre-commit  (gate enforcement; falls back to .claude/hooks/gate-enforce.py)"
    fi
  else
    echo "  ! $TARGET has no .git — skipping git pre-commit install."
  fi
}

echo "Installing claude-codex-skills into: $TARGET   (mode=$MODE, $([ "$LINK" -eq 1 ] && echo symlink || echo copy))"
install_skills
install_hook_file
case "$MODE" in
  claude) claude_extras ;;
  codex)  codex_extras ;;
  both)   claude_extras; echo; codex_extras ;;
esac
echo
echo "Done. Requirement: both 'claude' and 'codex' CLIs on PATH and signed in."
