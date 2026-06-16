---
name: codex-gate
description: Per-task dual-validation gate between two AI coding CLIs (Claude Code and OpenAI Codex). After the DRIVER implements a numbered plan task, this skill runs an INDEPENDENT review of the uncommitted changes by the COUNTERPART model against the task's acceptance criteria, hunting for hollow-shell deliveries (stubs/TODO/mock passed off as done) and hallucinated APIs. A task CANNOT be marked complete until the reviewer returns APPROVED; otherwise the loop stays on the task. Bidirectional — works Claude→Codex and Codex→Claude. Use when executing any plan task, or when asked to "validate with codex/claude", "run the gate", or before marking a plan subitem [x].
user_invocable: true
---

# Cross-Model Gate — independent per-task validation

Every numbered task in a plan's `PROGRESS.md` must pass an **independent review
by the counterpart model** before its checkbox can be flipped to `[x]`. The gate
exists to stop hallucinations and hollow implementation shells from being
recorded as delivered work.

When Claude Code is the driver, **Codex** is the reviewer. When Codex is the
driver, **Claude** is the reviewer. The skill name is historical ("codex-gate");
the gate is symmetric.

When the driver is **Claude Code**, enforcement is deterministic via the
`gate-enforce` PostToolUse hook: a `[x]` task with no
`<plans>/<slug>/codex-gate/<ID>.md` containing `GATE_VERDICT: APPROVED` is
**blocked**. For other drivers, the same `gate-enforce.py` can run as a git
pre-commit hook (see the repo's `hooks/` and `docs/INSTALL.md`).

## Roles & Direction (read first)

You are the **DRIVER** (you implemented the task). The reviewer is your
counterpart:

| If you are…          | Reviewer | `gate.sh --reviewer` |
| -------------------- | -------- | -------------------- |
| **Claude Code**      | Codex    | `codex`              |
| **OpenAI Codex CLI** | Claude   | `claude`             |

> Requirement: BOTH `claude` and `codex` CLIs installed and signed in, because
> the driver shells out to the counterpart for the review.

## When this runs

After you believe a numbered task (e.g. `1.1`) is implemented — with its changes
**uncommitted** in the affected repo — and BEFORE committing or marking it `[x]`.

## Protocol (per task)

1. **Driver self-review (integrity).** Re-read the task's acceptance criteria and
   EVERY subtask. Confirm against the actual diff: real logic (not `TODO`/stub/
   `return true`/mock/empty handler), tests present and meaningful, no invented
   APIs/imports, behavior matches the plan's intent. Fix obvious gaps first — do
   not hand the reviewer a draft you already know is hollow.
2. **Assemble review instructions.** Copy `templates/review-instructions.md` to a
   temp file and fill in: task ID, title, the full acceptance criteria + subtasks,
   and any plan-specific rules. The template already mandates the verdict marker.
3. **Run the gate.** Installed skills live under `.claude/skills/` (Claude Code)
   or `.agents/skills/` (Codex), so resolve the skill directory first:

   ```bash
   SKILL_DIR="$(ls -d \
     "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills/codex-gate" \
     "$PWD/.agents/skills/codex-gate" \
     "$PWD/.claude/skills/codex-gate" 2>/dev/null | head -1)"

   bash "$SKILL_DIR"/scripts/gate.sh \
     --reviewer <codex|claude> \
     --task <ID> --repo <REPO_DIR> --slug <SLUG> --instructions <TMP_FILE>
   ```

   It reviews the uncommitted diff in read-only mode, writes the full review to
   `<plans>/<slug>/codex-gate/<ID>.md`, appends a row to `VERDICTS.md`, and exits
   `0`=APPROVED, `1`=CHANGES_REQUESTED, `2`=error/timeout.

4. **React to the verdict:**
   - **APPROVED (exit 0):** commit the task as a coherent unit, then mark it `[x]`
     in PROGRESS.md. The enforcement hook will pass.
   - **CHANGES_REQUESTED (exit 1):** read `codex-gate/<ID>.md` for the blockers,
     apply real fixes (NOT cosmetic silencing), and **re-run the gate**. Stay on
     this task.
   - **ERROR (exit 2):** inspect the review file. If the reviewer was
     unavailable/timed out, retry once. Persistent error → treat as not-approved
     (fail-closed).
5. **Loop bound + escalation.** Repeat steps 1–4 up to **5 rounds**. If the
   reviewer still returns CHANGES_REQUESTED after 5 rounds, STOP, summarize the
   unresolved blockers + the driver's counter-position, and escalate to the user
   to arbitrate. Never mark the task `[x]` to escape the loop.

## Granularity

The gate runs at the **numbered-task** level (`1.1`, `1.2`, …). The review
instructions REQUIRE the reviewer to verify every listed subtask individually —
so each subitem is validated, without a separate run per bullet.

## Model pinning & configuration

Defaults (override via environment):

| Variable            | Default   | Purpose                             |
| ------------------- | --------- | ----------------------------------- |
| `GATE_CODEX_MODEL`  | `auto`    | Codex model when Codex reviews      |
| `GATE_CODEX_EFFORT` | `xhigh`   | Codex reasoning effort              |
| `GATE_CLAUDE_MODEL` | `opus`    | Claude model when Claude reviews    |
| `GATE_PLANS_DIR`    | `plans`   | Root directory of plans/PROGRESS.md |
| `GATE_TIMEOUT`      | `600`     | Per-review timeout in seconds       |

Each `*_MODEL` accepts a concrete model/alias (pin, for reproducibility) or
`auto` (defer to the CLI's own default). The Claude default `opus` is an alias
that always resolves to the **latest Opus** — the most-capable Claude with zero
maintenance. The Codex CLI has **no "latest" alias**, so this package defaults
to `auto`; set `GATE_CODEX_MODEL` to a concrete model id when you need pinned
reviews.

## What this skill does NOT do

| Action                                        | Allowed? |
| --------------------------------------------- | -------- |
| Run the counterpart review in read-only       | YES      |
| Write review + ledger files                   | YES      |
| Mark a task `[x]` without an APPROVED review  | NO       |
| Let the reviewer modify files (write mode)    | NO       |
| Silence/bypass a CHANGES_REQUESTED verdict    | NO       |
| Loop unbounded (must escalate after 5 rounds) | NO       |
