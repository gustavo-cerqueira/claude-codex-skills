# Directions: how bidirectionality works

Both skills are written once and run in **two directions**. The agent that loads
the skill is always the **driver**; the **counterpart** model is always the
reviewer (and, for `claude-codex-plan`, the eventual executor).

```
Forward  (Claude Code is driver):   Claude plans/implements  →  Codex reviews
Reverse  (OpenAI Codex is driver):  Codex  plans/implements  →  Claude reviews
```

## Single source, both directions

Both CLIs discover skills from the same files:

- **Claude Code** reads `.claude/skills/<name>/SKILL.md`.
- **OpenAI Codex** reads skills under `.agents/skills/<name>/SKILL.md`.

The recommended setup makes `.agents` a symlink to `.claude`, so a single skill
folder serves both CLIs. `install.sh --mode both` (or `--mode codex`) creates
that symlink for you.

Because the skill text is read by _whichever_ CLI is driving, each SKILL.md tells
the driver to identify itself and pick the counterpart:

| Driver (loads the skill) | Counterpart (reviewer) | Invoked via    |
| ------------------------ | ---------------------- | -------------- |
| Claude Code              | Codex                  | `codex exec …` |
| OpenAI Codex             | Claude                 | `claude -p …`  |

The counterpart is invoked by a small wrapper script that branches on a
`--reviewer codex|claude` flag, so the phase instructions stay identical in both
directions.

## How the counterpart is called

### Reviewing (read-only) — both skills

| Reviewer | Command (read-only)                                                                        |
| -------- | ------------------------------------------------------------------------------------------ |
| Codex    | `codex exec -s read-only -m <model> -c model_reasoning_effort=<effort> -C <repo> -o <out>` |
| Claude   | `claude -p --allowedTools "Read Grep Glob" --output-format text [--model <model>]`         |

- **Codex** review is locked to read-only with `-s read-only`.
- **Claude** review is locked to read-only by whitelisting only `Read Grep Glob`
  (no `Edit`/`Write`/`Bash`), so the reviewer can inspect the repo to catch
  hallucinations but cannot modify anything.

### The verdict marker is reviewer-agnostic

Codex can be forced into a JSON output schema (`--output-schema`); Claude cannot.
So the gate uses a single normalized sentinel both reviewers emit and the hook
greps for:

```
GATE_VERDICT: APPROVED
GATE_VERDICT: CHANGES_REQUESTED
```

For Codex the structured JSON `{verdict, blockers, summary}` is parsed; for Claude
the sentinel line is parsed. Either way the review file ends with one
`GATE_VERDICT:` line, which is the single source of truth for enforcement.

## Enforcement per direction

| Driver      | Enforcement mechanism                                                                                              |
| ----------- | ------------------------------------------------------------------------------------------------------------------ |
| Claude Code | `gate-enforce.py` as a **PostToolUse** hook: blocks writing a `[x]` PROGRESS.md task without an `APPROVED` review. |
| Codex / any | `gate-enforce.py` (CLI mode) as a **git pre-commit** hook: blocks the commit instead.                              |

Both modes share the exact same invariant check, so the gate behaves identically
no matter who drove the work. A non-code task can opt out with an explicit
`Gate: N/A` marker inside its block in `PROGRESS.md`.

## Why not just one direction?

You can use only the forward direction (Claude drives, Codex reviews) and never
touch the reverse — it works standalone. The reverse direction exists so that a
Codex-primary workflow gets the same second-opinion safety net from Claude. The
package ships both so the choice is yours per project or per task.
