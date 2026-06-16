---
name: claude-codex-plan
description: Collaborative planning between two AI coding CLIs (Claude Code and OpenAI Codex). The DRIVER (whichever CLI loaded this skill) plans; the COUNTERPART model reviews (replica), the driver refines, the counterpart counter-reviews (treplica), then the driver writes a final consensus + a ready-to-paste execution prompt. Bidirectional from one source — works Claude→Codex and Codex→Claude. All communication via numbered .md files for auditability.
user_invocable: true
---

# Claude ⇄ Codex Collaborative Plan

A multi-phase planning skill where **two different AI coding CLIs debate a plan**
via `.md` files until they reach consensus. One model drives (authors the plan),
the other acts as an adversarial reviewer. The final output is a ready-to-paste
prompt for the counterpart model to execute.

This skill is **bidirectional from a single source file**: it runs the same way
no matter which CLI loaded it.

## Roles & Direction (read first)

You — the agent reading this skill — are the **DRIVER**. Identify your
counterpart and set the reviewer flag accordingly:

| If you are…          | DRIVER (plans/refines/decides) | COUNTERPART (reviews + later executes) | `reviewer.sh --reviewer` |
| -------------------- | ------------------------------ | -------------------------------------- | ------------------------ |
| **Claude Code**      | Claude                         | Codex (`codex exec`)                   | `codex`                  |
| **OpenAI Codex CLI** | Codex                          | Claude (`claude -p`)                   | `claude`                 |

The helper script `scripts/reviewer.sh` abstracts the counterpart CLI, so the
phases below are written once and apply in both directions. Throughout this
document, **REVIEWER** = the counterpart model, **DRIVER** = you.

> Requirement: BOTH CLIs (`claude` and `codex`) must be installed and signed in
> with active subscriptions, since the driver shells out to the counterpart.

### Locate the skill directory

Installed skills live under `.claude/skills/` (Claude Code) or `.agents/skills/`
(Codex), NOT at the project root. Resolve the skill directory once and reuse it
for every script call below:

```bash
SKILL_DIR="$(ls -d \
  "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills/claude-codex-plan" \
  "$PWD/.agents/skills/claude-codex-plan" \
  "$PWD/.claude/skills/claude-codex-plan" 2>/dev/null | head -1)"
```

## Contents

- [Workflow Overview](#workflow-overview)
- [Phase 1: Planning (Driver)](#phase-1-planning-driver)
- [Phase 2: Replica (Reviewer)](#phase-2-replica-reviewer)
- [Phase 3a: Refinement (Driver)](#phase-3a-refinement-driver)
- [Phase 3b: Treplica (Reviewer)](#phase-3b-treplica-reviewer)
- [Phase 4: Consensus (Driver)](#phase-4-consensus-driver)
- [File Structure](#file-structure)
- [Reviewer Integration](#reviewer-integration)
- [Prompt Templates](#prompt-templates)

---

## Workflow Overview

```
User Request: /claude-codex-plan "task description"
    |
    v
[1. PLANNING]   Driver analyzes repo, creates 01_plan.md
    |
    v
[2. REPLICA]    Reviewer critiques the plan -> 02_reviewer_replica.md
    |
    v
[3a. REFINEMENT] Driver answers the critique -> 03_driver_refinement.md
    |
    v
[3b. TREPLICA]  Reviewer re-reviews with full context -> 04_reviewer_treplica.md
    |
    v
[4. CONSENSUS]  Driver synthesizes the debate:
    ├── 05_final_consensus.md     (the debated plan)
    └── 06_execution_prompt.md    (ready to paste into the COUNTERPART CLI)
    |
    v
████ MANDATORY STOP ████
User pastes 06_execution_prompt.md into the counterpart CLI for execution.
```

The plans live under `${COLLAB_PLANS_DIR:-plans}/<slug>/`. Pick a short
kebab-case `<slug>` from the task title.

---

## Phase 1: Planning (Driver)

### Step 1.1: Analyze the repository

Use your read/search tools to understand: current state relevant to the task,
files that will be affected, existing patterns and conventions, dependencies and
constraints.

### Step 1.2: Create `01_plan.md`

Copy `templates/plan.md` and fill it in. It captures: Objective, Context, Current
State Analysis, Proposed Approach (numbered steps with files + rationale),
Architecture Decisions, Known Risks, Out of Scope, Validation Criteria, and any
Project Rules from your agent instructions (`CLAUDE.md` / `AGENTS.md`).

### Step 1.3: Show the plan and offer to proceed

Display the plan and ask the user whether to send it to the reviewer.

---

## Phase 2: Replica (Reviewer)

The counterpart model reviews the plan and finds edge cases, risks, and gaps.

### Step 2.1: Build the review prompt

Concatenate `templates/replica-prompt.md` (the reviewer instructions) followed by
the full content of `01_plan.md` into a temp file:

```bash
REPLICA_PROMPT="$(mktemp "${TMPDIR:-/tmp}/replica_prompt.XXXXXX")"
cat "$SKILL_DIR/templates/replica-prompt.md" \
  "${COLLAB_PLANS_DIR:-plans}/<slug>/01_plan.md" > "$REPLICA_PROMPT"
```

### Step 2.2: Run the reviewer (read-only)

```bash
bash "$SKILL_DIR"/scripts/reviewer.sh \
  --reviewer <codex|claude> \
  --prompt "$REPLICA_PROMPT" \
  --out "${COLLAB_PLANS_DIR:-plans}/<slug>/02_reviewer_replica.md" \
  --repo .
```

The script runs the counterpart in **read-only** mode (it must not modify files
during review) and writes the response to the numbered file. See
[Reviewer Integration](#reviewer-integration) for the exact CLI flags.

### Step 2.3: Verify output

Confirm `02_reviewer_replica.md` is non-empty, read it, and show it to the user.
If it failed or is empty, inform the user and offer to retry.

---

## Phase 3a: Refinement (Driver)

### Step 3a.1: Triage the critique

Read `02_reviewer_replica.md` and categorize each point: **valid edge case**
(incorporate), **valid risk** (add mitigation), **disagreement** (explain why the
plan is still correct, with evidence), **new suggestion** (accept/reject with
reasoning).

### Step 3a.2: Create `03_driver_refinement.md`

Document Accepted Points (with the action taken + which step changed), Rejected
Points (with reasoning + code/architecture evidence), the Updated Plan, any New
Risks, and Open Questions for the final review.

---

## Phase 3b: Treplica (Reviewer)

The reviewer receives ALL accumulated context and gives a final review.

### Step 3b.1: Build the accumulated prompt

Concatenate `templates/treplica-prompt.md` followed by the full content of
`01_plan.md`, `02_reviewer_replica.md`, and `03_driver_refinement.md` into
a temp file:

```bash
TREPLICA_PROMPT="$(mktemp "${TMPDIR:-/tmp}/treplica_prompt.XXXXXX")"
cat "$SKILL_DIR/templates/treplica-prompt.md" \
  "${COLLAB_PLANS_DIR:-plans}/<slug>/01_plan.md" \
  "${COLLAB_PLANS_DIR:-plans}/<slug>/02_reviewer_replica.md" \
  "${COLLAB_PLANS_DIR:-plans}/<slug>/03_driver_refinement.md" > "$TREPLICA_PROMPT"
```

### Step 3b.2: Run the reviewer (read-only)

```bash
bash "$SKILL_DIR"/scripts/reviewer.sh \
  --reviewer <codex|claude> \
  --prompt "$TREPLICA_PROMPT" \
  --out "${COLLAB_PLANS_DIR:-plans}/<slug>/04_reviewer_treplica.md" \
  --repo .
```

### Step 3b.3: Verify and display

Confirm `04_reviewer_treplica.md` exists, is non-empty, and show it to the user.

---

## Phase 4: Consensus (Driver)

### Step 4.1: Analyze the treplica

Determine: **full agreement**, **partial agreement** (incorporate valid new
points), or **remaining disagreement** (document both perspectives; the driver
makes the final call with justification).

### Step 4.2: Create `05_final_consensus.md`

Include: Debate Summary (4 rounds, consensus level), Points of Agreement, Resolved
Disputes (both positions + resolution), the Final Plan (numbered steps with files,
edge cases from review, validation), Architecture Decisions (consensus), a
combined Risk Matrix, final Validation Criteria, and a Project Rules checklist.

### Step 4.3: Create `06_execution_prompt.md`

A self-contained prompt the COUNTERPART model will execute in write mode. It must
contain:

1. A **debate-history table** (files 01–05: phase, path, author, summary) so the
   executor knows _why_ decisions were made.
2. **Key locked decisions** — the most important resolved disputes (so the
   executor does not re-litigate them).
3. Project context (structure, stack, how to run/build/test).
4. The complete consensus plan from `05_final_consensus.md`.
5. Step-by-step implementation instructions with file paths + expected changes.
6. Project rules that MUST be followed.
7. Validation commands to run after each step.
8. What NOT to do (out of scope, prohibited patterns).

### Step 4.4: Present and STOP

```
================================================================
COLLABORATIVE PLAN COMPLETE

Debate files (in ${COLLAB_PLANS_DIR:-plans}/<slug>/):
  01_plan.md                 <- Driver's initial plan
  02_reviewer_replica.md     <- Reviewer critique (edge cases)
  03_driver_refinement.md    <- Driver's refinement
  04_reviewer_treplica.md    <- Reviewer final review
  05_final_consensus.md      <- Final consensus
  06_execution_prompt.md     <- PASTE THIS INTO THE COUNTERPART CLI

Next step:
  Copy 06_execution_prompt.md into the counterpart CLI to execute.
  (Claude drove -> paste into Codex.  Codex drove -> paste into Claude.)
================================================================
```

**Then STOP. Do not execute anything.**

---

## File Structure

```
${COLLAB_PLANS_DIR:-plans}/<slug>/
├── 01_plan.md                 <- Driver  (Phase 1)
├── 02_reviewer_replica.md     <- Reviewer via reviewer.sh (Phase 2)
├── 03_driver_refinement.md    <- Driver  (Phase 3a)
├── 04_reviewer_treplica.md    <- Reviewer via reviewer.sh (Phase 3b)
├── 05_final_consensus.md      <- Driver  (Phase 4)
└── 06_execution_prompt.md     <- Driver  (Phase 4)
```

Rules:

- Numbered sequentially for chronological traceability.
- Each file references its predecessors (accumulated context).
- Reviewer files (02, 04) are generated exclusively via `reviewer.sh`.
- Driver files (01, 03, 05, 06) are generated by the driving CLI.
- All files stay in the repo for auditability.

---

## Reviewer Integration

`scripts/reviewer.sh` selects the counterpart CLI and applies the configured
model policy:

```bash
# Claude drives -> Codex reviews (read-only):
codex exec -s read-only [-m "$CODEX_MODEL"] [-c model_reasoning_effort="$CODEX_EFFORT"] -C <repo> -o <out> < <prompt>

# Codex drives -> Claude reviews (read-only tools only):
claude -p < <prompt>  --allowedTools "Read Grep Glob" --output-format text  [--model "$CLAUDE_MODEL"]  > <out>
```

Configurable via environment (defaults in parentheses):

| Variable              | Default   | Purpose                                |
| --------------------- | --------- | -------------------------------------- |
| `COLLAB_CODEX_MODEL`  | `auto`    | Codex model when Codex is the reviewer |
| `COLLAB_CODEX_EFFORT` | `xhigh`   | Codex reasoning effort                 |
| `COLLAB_CLAUDE_MODEL` | `opus`    | Claude model when Claude reviews       |
| `COLLAB_PLANS_DIR`    | `plans`   | Root directory for debate files        |

### Choosing the counterpart model

Each `*_MODEL` accepts: a concrete model/alias (pin), or `auto` (defer to the
CLI's own default — Codex: `~/.codex/config.toml`; Claude: session default).

- **Claude reviewer:** the default `opus` is an alias that **always resolves to
  the latest Opus**, so the most-capable Claude tracks new releases with zero
  maintenance (`sonnet`/`fable` are also valid aliases).
- **Codex reviewer:** the Codex CLI has **no "latest/flagship" alias and no
  model-list command**, so this package defaults to `auto` and inherits the
  user's Codex config. Set `COLLAB_CODEX_MODEL` to a concrete model id when you
  need pinned reviews.

Pinning aids **reproducibility/auditability** (the model is recorded in the
debate trail); `auto` favors never going stale. Pick per project.

### Error handling

- Reviewer CLI not on PATH → the script exits non-zero with a clear message.
- Empty output → the script fails; inform the user and offer retry.
- Timeout / very large plan → suggest splitting the plan into smaller sections.

---

## Prompt Templates

The reviewer prompts live in `templates/`:

- `templates/replica-prompt.md` — Phase 2 adversarial first review.
- `templates/treplica-prompt.md` — Phase 3b final review with full debate context.

Prepend the relevant template to the accumulated `.md` content (see each phase).

---

## Activation Triggers

- `/claude-codex-plan "task description"` — start collaborative planning.
- "plan with codex…", "plan with claude…", "collaborative plan for…".

---

## What this skill does NOT do

| Action                                       | Allowed? |
| -------------------------------------------- | -------- |
| Analyze the repository                       | YES      |
| Create plan `.md` files                      | YES      |
| Run the counterpart in read-only review mode | YES      |
| Generate the execution prompt                | YES      |
| Execute the plan                             | NO       |
| Run the counterpart in write mode            | NO       |
| Modify code files                            | NO       |
| Auto-paste into the counterpart CLI          | NO       |
