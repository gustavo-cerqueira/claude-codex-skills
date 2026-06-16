#!/usr/bin/env python3
"""gate-enforce — deterministic enforcement of the cross-model per-task gate.

Invariant: in a plan's PROGRESS.md, every numbered task marked `[x]` MUST either
  - have an APPROVED review at  <plans>/<slug>/codex-gate/<ID>.md  (a file ending
    with the line `GATE_VERDICT: APPROVED`), OR
  - carry an explicit `Gate: N/A` marker inside its block (for non-code tasks:
    git/branch setup, decisions/ADRs, verification phases).

Two modes (auto-detected):
  1. Claude Code PostToolUse hook — reads a JSON event on stdin, extracts the
     written file_path, enforces only when it is a PROGRESS.md. Blocks with
     exit code 2 (which Claude Code surfaces to the model).
  2. CLI / git hook — pass one or more PROGRESS.md paths as argv. Prints any
     violations and exits 1 if found (usable from a git pre-commit hook).

Fail-open on malformed/irrelevant input; fail-closed only on the specific
invariant. Configure the plans dir name(s) via GATE_PLANS_DIR (default 'plans';
'plans_claude' is always also accepted for backward compatibility).
"""
import sys
import os
import re
import json

APPROVED_MARK = "GATE_VERDICT: APPROVED"
# Task-level checked items, e.g. "- [x] **1.1 ...":
CHECKED_RE = re.compile(r"^\s*-\s*\[x\]\s*\*\*([0-9]+\.[0-9]+)\b", re.M)
# Block boundary: the next task line (any state) or a markdown heading.
BLOCK_BOUND_RE = re.compile(r"^\s*-\s*\[[ xX]\]\s*\*\*|^#{2,4}\s", re.M)
# Explicit, auditable exemption for non-code tasks.
EXEMPT_RE = re.compile(r"Gate:\s*N/?A", re.I)


def _plans_dirs():
    dirs = {os.environ.get("GATE_PLANS_DIR", "plans"), "plans", "plans_claude"}
    return {d for d in dirs if d}


def _is_progress_file(fp: str) -> bool:
    norm = fp.replace("\\", "/")
    m = re.search(r"(?:^|/)([^/]+)/[^/]+/PROGRESS\.md$", norm)
    return bool(m and m.group(1) in _plans_dirs())


def check_progress(fp: str):
    """Return the list of task IDs that violate the gate invariant in this file."""
    if not os.path.isfile(fp):
        return []
    slug_dir = os.path.dirname(fp)
    gate_dir = os.path.join(slug_dir, "codex-gate")
    try:
        text = open(fp, encoding="utf-8", errors="replace").read()
    except Exception:
        return []

    missing = []
    for m in CHECKED_RE.finditer(text):
        tid = m.group(1)
        nb = BLOCK_BOUND_RE.search(text, m.end())
        block = text[m.start(): nb.start() if nb else len(text)]
        if EXEMPT_RE.search(block):
            continue  # explicitly exempt non-code task
        review = os.path.join(gate_dir, f"{tid}.md")
        ok = False
        if os.path.isfile(review):
            try:
                ok = APPROVED_MARK in open(review, encoding="utf-8", errors="replace").read()
            except Exception:
                ok = False
        if not ok:
            missing.append(tid)
    return missing


def _message(fp: str, missing) -> str:
    ids = ", ".join(missing)
    return (
        f"BLOCKED by cross-model gate ({fp}): task(s) {ids} are marked [x] without "
        "an APPROVED counterpart review and without a `Gate: N/A` exemption. Run "
        "the `codex-gate` skill for each (scripts/gate.sh) so "
        "codex-gate/<ID>.md ends with 'GATE_VERDICT: APPROVED', or revert the "
        "checkbox to [ ]. Non-code tasks may carry an explicit `Gate: N/A` line. "
        "Never mark a task complete to escape a CHANGES_REQUESTED verdict.\n"
    )


def _cli_mode(paths) -> int:
    rc = 0
    for fp in paths:
        if not _is_progress_file(fp):
            continue
        missing = check_progress(fp)
        if missing:
            sys.stderr.write(_message(fp, missing))
            rc = 1
    return rc


def _hook_mode() -> int:
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        return 0  # unparseable → don't interfere
    ti = payload.get("tool_input", {}) or {}
    fp = ti.get("file_path") or ti.get("filePath") or ""
    if not _is_progress_file(fp):
        return 0
    missing = check_progress(fp)
    if missing:
        sys.stderr.write(_message(fp, missing))
        return 2  # Claude Code surfaces stderr to the model and blocks
    return 0


def main() -> int:
    if len(sys.argv) > 1:
        return _cli_mode(sys.argv[1:])
    return _hook_mode()


if __name__ == "__main__":
    sys.exit(main())
