#!/usr/bin/env bash
# reviewer.sh — invoke the COUNTERPART AI coding CLI as a READ-ONLY reviewer.
#
# Bidirectional helper for the `claude-codex-plan` skill:
#   Forward  (Claude drives):  --reviewer codex   -> codex exec  (read-only)
#   Reverse  (Codex  drives):  --reviewer claude  -> claude -p   (read-only tools)
#
# Usage:
#   reviewer.sh --reviewer <codex|claude> --prompt <FILE> --out <FILE> [--repo <DIR>]
#
# Env (defaults): COLLAB_CODEX_MODEL=gpt-5.5  COLLAB_CODEX_EFFORT=xhigh
#                 COLLAB_CLAUDE_MODEL=(unset -> CLI default)
# Exit: 0 = review written · 2 = error/empty output
set -uo pipefail

CODEX_MODEL="${COLLAB_CODEX_MODEL:-gpt-5.5}"
CODEX_EFFORT="${COLLAB_CODEX_EFFORT:-xhigh}"
CLAUDE_MODEL="${COLLAB_CLAUDE_MODEL:-}"

REVIEWER=""; PROMPT=""; OUT=""; REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reviewer) REVIEWER="$2"; shift 2 ;;
    --prompt)   PROMPT="$2";   shift 2 ;;
    --out)      OUT="$2";      shift 2 ;;
    --repo)     REPO="$2";     shift 2 ;;
    *) echo "reviewer.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$REVIEWER" ] && [ -n "$PROMPT" ] && [ -n "$OUT" ] || {
  echo "reviewer.sh: need --reviewer <codex|claude> --prompt <FILE> --out <FILE>" >&2; exit 2; }
[ -f "$PROMPT" ] || { echo "reviewer.sh: prompt file not found: $PROMPT" >&2; exit 2; }

# Resolve to absolute paths so an internal `cd` (claude branch) cannot break them.
case "$PROMPT" in /*) ;; *) PROMPT="$PWD/$PROMPT" ;; esac
case "$OUT"    in /*) ;; *) OUT="$PWD/$OUT" ;; esac
mkdir -p "$(dirname "$OUT")"

case "$REVIEWER" in
  codex)
    command -v codex >/dev/null 2>&1 || { echo "reviewer.sh: codex CLI not on PATH" >&2; exit 2; }
    args=( exec -s read-only -m "$CODEX_MODEL" -c model_reasoning_effort="$CODEX_EFFORT" )
    [ -n "$REPO" ] && args+=( -C "$REPO" )
    args+=( -o "$OUT" )
    codex "${args[@]}" < "$PROMPT"
    ;;
  claude)
    command -v claude >/dev/null 2>&1 || { echo "reviewer.sh: claude CLI not on PATH" >&2; exit 2; }
    cargs=( -p --allowedTools "Read Grep Glob" --output-format text )
    [ -n "$CLAUDE_MODEL" ] && cargs+=( --model "$CLAUDE_MODEL" )
    ( [ -n "$REPO" ] && cd "$REPO"; claude "${cargs[@]}" < "$PROMPT" ) > "$OUT"
    ;;
  *)
    echo "reviewer.sh: --reviewer must be 'codex' or 'claude'" >&2; exit 2 ;;
esac

[ -s "$OUT" ] || { echo "reviewer.sh: $REVIEWER produced empty output: $OUT" >&2; exit 2; }
echo "reviewer.sh: $REVIEWER review written to $OUT"
