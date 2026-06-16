#!/usr/bin/env python3
"""gate-enforce — deterministic enforcement of the cross-model per-task gate.

Invariant: in a plan's PROGRESS.md, every numbered task marked `[x]`/`[X]` MUST
either
  - have an APPROVED review at  <slug>/codex-gate/<ID>.md  whose LAST
    `GATE_VERDICT:` line is exactly `APPROVED`, OR
  - carry an explicit exemption for non-code tasks: `(Gate: N/A)` on the task
    line, or a dedicated `Gate: N/A` line inside the task block.

Modes (auto-detected):
  1. Claude Code PostToolUse hook — reads a JSON event on stdin, extracts the
     written file_path, enforces only when it is a PROGRESS.md. Blocks with
     exit code 2 (surfaced to the model).
  2. CLI / git hook — either:
       gate-enforce.py <PROGRESS.md> [<PROGRESS.md> ...]      (check on disk)
       gate-enforce.py --progress <FILE> --gate-base <DIR>    (check FILE's
           content, resolve codex-gate/ under DIR — used by the pre-commit hook
           to validate the STAGED content while resolving reviews in the tree)
     Exits 1 if any violation is found (usable from a git pre-commit hook).

Fail-open on malformed/irrelevant input; fail-closed only on the specific
invariant. The plans dir name defaults to 'plans'; override with GATE_PLANS_DIR.
"""
import sys
import os
import re
import json

# Task-level checked items, e.g. "- [x] **1.1 ..." or "- [X] **1.1 ...":
CHECKED_RE = re.compile(r"^\s*-\s*\[[xX]\]\s*\*\*([0-9]+\.[0-9]+)\b", re.M)
# Block boundary: the next task line (any state) or a markdown heading.
BLOCK_BOUND_RE = re.compile(r"^\s*-\s*\[[ xX]\]\s*\*\*|^#{2,4}\s", re.M)
# Explicit, auditable exemptions for non-code tasks.
EXEMPT_INLINE_RE = re.compile(r"\(\s*Gate:\s*N/?A\s*\)", re.I)              # on task line
EXEMPT_LINE_RE = re.compile(r"^\s*(?:[-*>]\s*)?Gate:\s*N/?A\s*$", re.I | re.M)  # dedicated line
# A normalized verdict line; the LAST one wins.
VERDICT_LINE_RE = re.compile(r"^\s*GATE_VERDICT:\s*(\S+)", re.M)


def _plans_dir() -> str:
    return os.environ.get("GATE_PLANS_DIR", "plans")


def _is_progress_file(fp: str) -> bool:
    norm = fp.replace("\\", "/")
    m = re.search(r"(?:^|/)([^/]+)/[^/]+/PROGRESS\.md$", norm)
    return bool(m and m.group(1) == _plans_dir())


def _review_approved(review_path: str) -> bool:
    """True only if the review file's LAST GATE_VERDICT line is APPROVED."""
    if not os.path.isfile(review_path):
        return False
    try:
        txt = open(review_path, encoding="utf-8", errors="replace").read()
    except Exception:
        return False
    verdicts = VERDICT_LINE_RE.findall(txt)
    return bool(verdicts) and verdicts[-1].strip().upper() == "APPROVED"


def check_progress_text(text: str, gate_base: str):
    """Return task IDs that violate the invariant. Reviews resolved under
    <gate_base>/codex-gate/."""
    gate_dir = os.path.join(gate_base, "codex-gate")
    missing = []
    for m in CHECKED_RE.finditer(text):
        tid = m.group(1)
        line_end = text.find("\n", m.start())
        header = text[m.start(): line_end if line_end != -1 else len(text)]
        nb = BLOCK_BOUND_RE.search(text, m.end())
        block = text[m.start(): nb.start() if nb else len(text)]
        if EXEMPT_INLINE_RE.search(header) or EXEMPT_LINE_RE.search(block):
            continue  # explicitly exempt non-code task
        if not _review_approved(os.path.join(gate_dir, f"{tid}.md")):
            missing.append(tid)
    return missing


def check_progress(fp: str):
    if not os.path.isfile(fp):
        return []
    try:
        text = open(fp, encoding="utf-8", errors="replace").read()
    except Exception:
        return []
    return check_progress_text(text, os.path.dirname(fp))


def _message(label: str, missing) -> str:
    ids = ", ".join(missing)
    return (
        f"BLOCKED by cross-model gate ({label}): task(s) {ids} are marked [x] "
        "without an APPROVED counterpart review and without a `Gate: N/A` "
        "exemption. Run the `codex-gate` skill for each (scripts/gate.sh) so "
        "codex-gate/<ID>.md ends with 'GATE_VERDICT: APPROVED', or revert the "
        "checkbox to [ ]. Non-code tasks may carry an explicit `(Gate: N/A)` "
        "marker. Never mark a task complete to escape a CHANGES_REQUESTED "
        "verdict.\n"
    )


def _cli_progress_mode(argv) -> int:
    """--progress FILE [--gate-base DIR]: check FILE content against reviews
    under DIR (defaults to dirname(FILE))."""
    progress = None
    gate_base = None
    label = None
    i = 0
    while i < len(argv):
        if argv[i] == "--progress" and i + 1 < len(argv):
            progress = argv[i + 1]; i += 2
        elif argv[i] == "--gate-base" and i + 1 < len(argv):
            gate_base = argv[i + 1]; i += 2
        elif argv[i] == "--label" and i + 1 < len(argv):
            label = argv[i + 1]; i += 2
        else:
            sys.stderr.write(f"gate-enforce: bad arg near '{argv[i]}'\n"); return 2
    if not progress or not os.path.isfile(progress):
        return 0  # nothing to check / fail-open on missing input
    if gate_base is None:
        gate_base = os.path.dirname(progress)
    try:
        text = open(progress, encoding="utf-8", errors="replace").read()
    except Exception:
        return 0
    missing = check_progress_text(text, gate_base)
    if missing:
        sys.stderr.write(_message(label or progress, missing))
        return 1
    return 0


def _cli_paths_mode(paths) -> int:
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
    # Resolve a relative path against the project dir so the hook never fails
    # open just because cwd differs from the project root.
    if fp and not os.path.isabs(fp):
        base = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
        fp = os.path.join(base, fp)
    if not _is_progress_file(fp):
        return 0
    missing = check_progress(fp)
    if missing:
        sys.stderr.write(_message(fp, missing))
        return 2  # Claude Code surfaces stderr to the model and blocks
    return 0


def main() -> int:
    if "--progress" in sys.argv[1:]:
        return _cli_progress_mode(sys.argv[1:])
    if len(sys.argv) > 1:
        return _cli_paths_mode(sys.argv[1:])
    return _hook_mode()


if __name__ == "__main__":
    sys.exit(main())
