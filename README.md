# claude-codex-skills

Two **bidirectional Agent Skills** that make [Claude Code](https://docs.claude.com/en/docs/claude-code)
and [OpenAI Codex](https://developers.openai.com/codex/cli) check each other's
work. You drive one CLI; it shells out to the other for an independent, deeper
opinion — across two complementary phases of software work:

| Skill                                                        | What it does                                                                                                                                                                                                                                                                |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[`claude-codex-plan`](skills/claude-codex-plan/SKILL.md)** | **Collaborative planning.** The driver writes a plan; the counterpart model reviews it (replica), the driver refines, the counterpart re-reviews (treplica), then the driver writes a consensus plan + a ready-to-paste execution prompt.                                   |
| **[`codex-gate`](skills/codex-gate/SKILL.md)**               | **Per-task validation gate.** After the driver implements a numbered task, the counterpart model independently reviews the _uncommitted diff_ and must return `APPROVED` before the task can be marked done. Catches hollow shells (stubs/TODO/mock) and hallucinated APIs. |

Both skills are **bidirectional from a single source**: whichever CLI loads the
skill is the **driver**, and the **other** model is always the reviewer/executor.

```
Claude Code drives  ──►  Codex reviews / executes      (forward)
Codex drives        ──►  Claude reviews / executes      (reverse)
```

## Why two subscriptions?

Two frontier models from different labs have different blind spots. Using one to
plan and the other to adversarially review — then gating task completion on the
reviewer's verdict — catches mistakes that a single model (however capable) tends
to wave through: optimistic plans, hollow implementations, and hallucinated APIs.
Everything is written to auditable `.md` files so you can see the whole debate.

## Requirements

- **Claude Code CLI** (`claude`) — signed in with an active subscription/API key.
- **OpenAI Codex CLI** (`codex`) — signed in with an active subscription/API key.
- `bash`, `git`, `python3` on `PATH`.

Both CLIs must be installed because the driver shells out to the counterpart.

## Install

```bash
git clone https://github.com/gustavo-cerqueira/claude-codex-skills.git
cd claude-codex-skills

# Install into a project (Claude Code + Codex). Symlinks by default so a future
# `git pull` here updates the installed skills automatically.
./install.sh --target /path/to/your/project --mode both
```

- `--mode claude` installs only the Claude Code wiring (`.claude/skills/` + hook).
- `--mode codex` only ensures the `.agents -> .claude` symlink Codex uses.
- `--copy` copies files instead of symlinking (self-contained install).
- `--force` replaces existing non-symlink skill/hook paths during reinstall.

After `--mode claude` the installer prints the `settings.json` snippet that
registers the deterministic enforcement hook. See [docs/INSTALL.md](docs/INSTALL.md)
for the full manual steps and [docs/DIRECTIONS.md](docs/DIRECTIONS.md) for how each
direction works.

## Usage

### Collaborative planning

In Claude Code **or** Codex:

```
/claude-codex-plan "add rate limiting to the public API"
```

The driver analyzes the repo and produces a numbered debate under
`plans/<slug>/`:

```
plans/<slug>/
├── 01_plan.md                 ← driver
├── 02_reviewer_replica.md     ← counterpart (read-only)
├── 03_driver_refinement.md    ← driver
├── 04_reviewer_treplica.md    ← counterpart (read-only)
├── 05_final_consensus.md      ← driver
└── 06_execution_prompt.md     ← paste this into the counterpart CLI to execute
```

### Per-task validation gate

While executing a plan, after you implement task `1.1` (changes still
uncommitted):

```
run the codex-gate for task 1.1
```

The counterpart reviews the uncommitted diff and writes
`plans/<slug>/codex-gate/1.1.md` ending in `GATE_VERDICT: APPROVED` or
`GATE_VERDICT: CHANGES_REQUESTED`, plus a row in `VERDICTS.md`. A task **cannot**
be marked `[x]` in `PROGRESS.md` until the review is `APPROVED` — enforced by
`hooks/gate-enforce.py` (a Claude Code PostToolUse hook, or a git pre-commit hook
for Codex-driven flows).

## Configuration

All behavior is controlled by environment variables (sensible defaults shown):

| Variable                                    | Default   | Used by            |
| ------------------------------------------- | --------- | ------------------ |
| `COLLAB_CODEX_MODEL` / `GATE_CODEX_MODEL`   | `auto`    | Codex as reviewer  |
| `COLLAB_CODEX_EFFORT` / `GATE_CODEX_EFFORT` | `xhigh`   | Codex reasoning    |
| `COLLAB_CLAUDE_MODEL` / `GATE_CLAUDE_MODEL` | `opus`    | Claude as reviewer |
| `COLLAB_PLANS_DIR` / `GATE_PLANS_DIR`       | `plans`   | Plan/debate root   |
| `GATE_TIMEOUT`                              | `600`     | Per-review timeout |

Copy `config.example.sh` to set these once (`source` it, or paste the lines into
your shell profile).

### Picking the counterpart model

Each `*_MODEL` variable accepts three policies:

1. **A concrete model or alias** — pins it exactly, for reproducible/auditable
   debates (e.g. `GATE_CODEX_MODEL=<codex-model-id>`, `GATE_CLAUDE_MODEL=claude-opus-4-8`).
2. **`auto`** — defers to that CLI's own default (Codex: `~/.codex/config.toml`;
   Claude: your session/config default). Never goes stale, but the model depends
   on each machine's config.
3. **The default** — `opus` for Claude, `auto` for Codex.

**Auto-selecting the _most capable_ model differs by vendor:**

- **Claude side:** the default `opus` is an **alias that always resolves to the
  latest Opus** (`claude --model opus`), so the most-capable Claude tracks new
  releases with **zero maintenance**. `sonnet`/`fable` are also valid aliases.
- **Codex side:** the Codex CLI exposes **no "latest/flagship" alias and no
  model-list command**, so this package defaults to `auto` and inherits your
  `~/.codex/config.toml` default. Set `*_CODEX_MODEL` to a concrete model id
  when you need reproducible, pinned reviews. This is a Codex CLI limitation, not
  a design choice — revisit if OpenAI adds a flagship alias.

## Repository layout

```
claude-codex-skills/
├── skills/
│   ├── claude-codex-plan/   SKILL.md + scripts/reviewer.sh + templates/
│   └── codex-gate/          SKILL.md + scripts/gate.sh    + templates/
├── hooks/
│   ├── gate-enforce.py      enforcement (Claude PostToolUse hook + git CLI mode)
│   └── pre-commit           CLI-agnostic git pre-commit wrapper
├── docs/
│   ├── INSTALL.md           detailed install for Claude Code and Codex
│   └── DIRECTIONS.md        how forward (Claude→Codex) and reverse work
├── install.sh
├── config.example.sh        pre-set models/behavior (source it)
├── LICENSE                  MIT
└── CHANGELOG.md
```

## Security & limitations

- **Your code goes to another vendor's model.** `codex-gate` embeds the
  uncommitted diff (including untracked files) into the reviewer's prompt and
  sends it to the counterpart model. Don't leave secrets in your working tree —
  the bundled `.gitignore` ignores `.env`, `*.pem`, `*.key`, etc.; review yours.
- **Prompt injection.** The diff is treated as untrusted data and the reviewer is
  told never to follow instructions embedded in it, but no LLM guardrail is
  perfect. Treat verdicts as advisory signal, not proof.
- **Enforcement layers differ.** The Claude Code PostToolUse hook only fires for
  `Edit|Write|MultiEdit` — a `PROGRESS.md` edited via `Bash` bypasses it. The
  **git pre-commit hook is the authoritative, CLI-agnostic backstop** and
  validates the _staged_ content. Install it (codex mode does this automatically).
- **Review files are trust-on-disk.** Enforcement reads `codex-gate/<ID>.md` and
  trusts its last `GATE_VERDICT:` line. A malicious or careless agent could forge
  one. The gate raises the cost of a hollow delivery; it is not a security
  boundary against a hostile actor with write access.
- **Large diffs are capped** (`GATE_DIFF_CAP`, default 200k chars). A truncated
  diff can never return `APPROVED` — the gate fails closed and tells you to split
  the task.

## A note on the names

These skills originated in a private workspace as `claude-codex-plan` and
`codex-gate`, named from the Claude-drives / Codex-reviews direction. The names
are kept for continuity; the behavior is symmetric — in the reverse direction the
roles simply swap (Codex drives, Claude reviews).

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md)
before proposing a change. Community PRs must pass review before they are merged;
the repository uses CODEOWNERS and branch protection so the maintainer keeps final
approval.

## Contributors

- **Gustavo Cerqueira** — creator and maintainer.
- **CODEX (OpenAI Codex)** — AI coding collaborator for packaging, review,
  documentation, and release hardening.

## License

[MIT](LICENSE) © 2026 Gustavo Cerqueira.
