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
# Env (defaults): COLLAB_CODEX_MODEL=auto  COLLAB_CODEX_EFFORT=xhigh
#                 COLLAB_CLAUDE_MODEL=(unset -> CLI default)
# Exit: 0 = review written · 2 = error/empty output
set -uo pipefail

# Model selection (per reviewer). Three policies per variable:
#   - a concrete model/alias  -> pinned (reproducible/auditable)
#   - "auto"                  -> defer to the CLI's own default (codex: ~/.codex/
#                                config.toml; claude: session/config default)
#   - (Claude default "opus") -> alias that ALWAYS resolves to the latest Opus,
#                                so the most-capable Claude tracks new releases
#                                with zero maintenance.
# NOTE: the Codex CLI exposes no "latest/flagship" alias and no model-list
# command, so this package defaults to "auto" instead of shipping a stale model
# id. Set COLLAB_CODEX_MODEL to a concrete id when you need pinned reviews.
CODEX_MODEL="${COLLAB_CODEX_MODEL:-auto}"
CODEX_EFFORT="${COLLAB_CODEX_EFFORT:-xhigh}"
CLAUDE_MODEL="${COLLAB_CLAUDE_MODEL:-opus}"

req() { [ "$1" -ge 2 ] || { echo "reviewer.sh: $2 needs a value" >&2; exit 2; }; }

REVIEWER=""; PROMPT=""; OUT=""; REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reviewer) req $# "$1"; REVIEWER="$2"; shift 2 ;;
    --prompt)   req $# "$1"; PROMPT="$2";   shift 2 ;;
    --out)      req $# "$1"; OUT="$2";      shift 2 ;;
    --repo)     req $# "$1"; REPO="$2";     shift 2 ;;
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
    args=( exec -s read-only )
    [ -n "$CODEX_MODEL" ]  && [ "$CODEX_MODEL"  != auto ] && args+=( -m "$CODEX_MODEL" )
    [ -n "$CODEX_EFFORT" ] && [ "$CODEX_EFFORT" != auto ] && args+=( -c model_reasoning_effort="$CODEX_EFFORT" )
    [ -n "$REPO" ] && args+=( -C "$REPO" )
    args+=( -o "$OUT" )
    codex "${args[@]}" < "$PROMPT"
    ;;
  claude)
    command -v claude >/dev/null 2>&1 || { echo "reviewer.sh: claude CLI not on PATH" >&2; exit 2; }
    cargs=( -p --allowedTools "Read Grep Glob" --output-format text )
    [ -n "$CLAUDE_MODEL" ] && [ "$CLAUDE_MODEL" != auto ] && cargs+=( --model "$CLAUDE_MODEL" )
    ( if [ -n "$REPO" ]; then cd "$REPO" || exit 2; fi; claude "${cargs[@]}" < "$PROMPT" ) > "$OUT"
    ;;
  *)
    echo "reviewer.sh: --reviewer must be 'codex' or 'claude'" >&2; exit 2 ;;
esac

[ -s "$OUT" ] || { echo "reviewer.sh: $REVIEWER produced empty output: $OUT" >&2; exit 2; }
echo "reviewer.sh: $REVIEWER review written to $OUT"
