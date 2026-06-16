#!/usr/bin/env bash
# gate.sh — independent cross-model review gate for ONE plan task.
#
# Reviews the UNCOMMITTED changes in <repo> against a task's acceptance criteria,
# hunting for hollow-shell deliveries (stubs/TODO/mock passed off as done) and
# hallucinated APIs. Emits a normalized `GATE_VERDICT:` marker the enforcement
# hook can gate the PROGRESS.md checkbox on.
#
# Bidirectional:
#   Forward  (Claude drives):  --reviewer codex   (default) -> codex exec (+ --output-schema)
#   Reverse  (Codex  drives):  --reviewer claude            -> claude -p  (read-only tools)
#
# Usage:
#   gate.sh --reviewer <codex|claude> --task <ID> --repo <DIR> --slug <SLUG> --instructions <FILE>
#
# Env: GATE_CODEX_MODEL(gpt-5.5) GATE_CODEX_EFFORT(xhigh) GATE_CLAUDE_MODEL(unset)
#      GATE_PLANS_DIR(plans) GATE_TIMEOUT(600)
# Exit: 0 = APPROVED · 1 = CHANGES_REQUESTED · 2 = ERROR/timeout/no-verdict
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$SCRIPT_DIR/../templates/verdict-schema.json"
CODEX_MODEL="${GATE_CODEX_MODEL:-gpt-5.5}"
CODEX_EFFORT="${GATE_CODEX_EFFORT:-xhigh}"
CLAUDE_MODEL="${GATE_CLAUDE_MODEL:-}"
PLANS_DIR="${GATE_PLANS_DIR:-plans}"
TIMEOUT="${GATE_TIMEOUT:-600}"

REVIEWER="codex"; TASK=""; REPO=""; SLUG=""; INSTR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reviewer)     REVIEWER="$2"; shift 2 ;;
    --task)         TASK="$2";     shift 2 ;;
    --repo)         REPO="$2";     shift 2 ;;
    --slug)         SLUG="$2";     shift 2 ;;
    --instructions) INSTR="$2";    shift 2 ;;
    --plans-dir)    PLANS_DIR="$2"; shift 2 ;;
    *) echo "gate.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$TASK" ] && [ -n "$REPO" ] && [ -n "$SLUG" ] && [ -n "$INSTR" ] || {
  echo "gate.sh: missing required args (--task --repo --slug --instructions)" >&2; exit 2; }
[ -f "$INSTR" ] || { echo "gate.sh: instructions file not found: $INSTR" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "gate.sh: python3 not on PATH" >&2; exit 2; }

case "$REPO" in /*) ;; *) REPO="$PROJECT_DIR/$REPO" ;; esac
[ -d "$REPO" ] || { echo "gate.sh: repo dir not found: $REPO" >&2; exit 2; }
INSTR_CONTENT="$(cat "$INSTR")"

GATE_DIR="$PROJECT_DIR/$PLANS_DIR/$SLUG/codex-gate"
mkdir -p "$GATE_DIR"
OUT="$GATE_DIR/${TASK}.md"
VJSON="$GATE_DIR/${TASK}.verdict.json"
LEDGER="$PROJECT_DIR/$PLANS_DIR/$SLUG/VERDICTS.md"
rm -f "$VJSON"

# Capture the uncommitted change set: tracked diff vs HEAD + untracked new files.
DIFF="$(cd "$REPO" && {
  git diff HEAD --no-color 2>/dev/null
  git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
    printf '\n--- NEW UNTRACKED FILE: %s ---\n' "$f"
    sed 's/^/+ /' "$f" 2>/dev/null
  done
})"
DIFF="${DIFF:0:200000}"  # cap prompt size

{ echo "<!-- gate | task=$TASK reviewer=$REVIEWER repo=$REPO | $(date -u +%FT%TZ) -->"; } >"$OUT"

if [ -z "${DIFF//[$' \t\n']/}" ]; then
  echo "" >>"$OUT"
  echo "GATE_VERDICT: NONE (no uncommitted changes — run the gate BEFORE committing the task)" >>"$OUT"
  echo "gate.sh: no uncommitted changes in $REPO to review." >&2
  exit 2
fi

PROMPT="$(printf '%s\n\n## UNCOMMITTED CHANGES UNDER REVIEW\n\nReview EXACTLY the diff below (the task'\''s uncommitted changes). You have read-only access to this repository — read other files to verify that referenced/imported symbols actually exist (catch hallucinations). Do NOT review unrelated pre-existing code.\n\n```diff\n%s\n```\n' "$INSTR_CONTENT" "$DIFF")"

VERDICT=""; rc=0

# Portable timeout (macOS lacks `timeout`): background + poll + hard-kill.
run_with_timeout() {  # $@ = command; reads $PROMPT on stdin; appends to $OUT
  ( printf '%s' "$PROMPT" | "$@" ) >>"$OUT" 2>&1 &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 3; waited=$((waited + 3))
    if [ "$waited" -ge "$TIMEOUT" ]; then
      kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null
      echo "(timeout after ${TIMEOUT}s)" >>"$OUT"; return 124
    fi
  done
  wait "$pid"; return $?
}

case "$REVIEWER" in
  codex)
    command -v codex >/dev/null 2>&1 || { echo "gate.sh: codex CLI not on PATH" >&2; exit 2; }
    [ -f "$SCHEMA" ] || { echo "gate.sh: verdict schema missing: $SCHEMA" >&2; exit 2; }
    run_with_timeout codex exec -s read-only -C "$REPO" \
      -m "$CODEX_MODEL" -c model_reasoning_effort="$CODEX_EFFORT" --ephemeral \
      --output-schema "$SCHEMA" -o "$VJSON"
    rc=$?
    VERDICT="$(python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1]))
    v=str(d.get("verdict","")).strip().upper()
    print(v if v in ("APPROVED","CHANGES_REQUESTED") else "")
except Exception:
    print("")' "$VJSON" 2>/dev/null)"
    if [ -f "$VJSON" ]; then
      { echo ""; echo "### Structured verdict"; echo '```json'; cat "$VJSON"; echo; echo '```'; } >>"$OUT"
    fi
    ;;
  claude)
    command -v claude >/dev/null 2>&1 || { echo "gate.sh: claude CLI not on PATH" >&2; exit 2; }
    cargs=( claude -p --allowedTools "Read Grep Glob" --output-format text )
    [ -n "$CLAUDE_MODEL" ] && cargs+=( --model "$CLAUDE_MODEL" )
    ( cd "$REPO" && run_with_timeout "${cargs[@]}" ); rc=$?
    # Claude has no enforced output schema: parse the sentinel line it was told to emit.
    VERDICT="$(grep -oE 'GATE_VERDICT:[[:space:]]*(APPROVED|CHANGES_REQUESTED)' "$OUT" \
                | tail -1 | grep -oE '(APPROVED|CHANGES_REQUESTED)')"
    ;;
  *)
    echo "gate.sh: --reviewer must be 'codex' or 'claude'" >&2; exit 2 ;;
esac

{ echo ""; echo "GATE_VERDICT: ${VERDICT:-NONE}"; } >>"$OUT"

ts="$(date -u +%FT%TZ)"
if [ ! -f "$LEDGER" ]; then
  { echo "# Cross-Model Gate Verdict Ledger — $SLUG";
    echo "";
    echo "Append-only. Each row = one independent review of a task's uncommitted changes.";
    echo "";
    echo "| timestamp (UTC) | task | verdict | reviewer/model | review file |";
    echo "| --------------- | ---- | ------- | -------------- | ----------- |"; } >"$LEDGER"
fi

if [ "$REVIEWER" = "codex" ]; then MODEL_LABEL="codex:$CODEX_MODEL/$CODEX_EFFORT"
else MODEL_LABEL="claude:${CLAUDE_MODEL:-default}"; fi

case "$VERDICT" in
  APPROVED)
    printf '| %s | %s | APPROVED | %s | codex-gate/%s.md |\n' "$ts" "$TASK" "$MODEL_LABEL" "$TASK" >>"$LEDGER"
    echo "gate.sh: APPROVED ($TASK) — review: $OUT"; exit 0 ;;
  CHANGES_REQUESTED)
    printf '| %s | %s | CHANGES_REQUESTED | %s | codex-gate/%s.md |\n' "$ts" "$TASK" "$MODEL_LABEL" "$TASK" >>"$LEDGER"
    echo "gate.sh: CHANGES_REQUESTED ($TASK) — read $OUT for blockers, fix, re-run." >&2; exit 1 ;;
  *)
    echo "gate.sh: NO VERDICT parsed (rc=$rc) — read $OUT; treat as not-approved." >&2; exit 2 ;;
esac
