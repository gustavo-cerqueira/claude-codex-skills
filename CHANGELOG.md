# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0]

### Added

- **`claude-codex-plan`** — bidirectional collaborative planning skill. The
  driver (Claude Code _or_ Codex) authors a plan; the counterpart model reviews
  it across two rounds (replica + treplica) until consensus, producing a
  ready-to-execute prompt. Works Claude→Codex and Codex→Claude from one source.
- **`codex-gate`** — bidirectional per-task validation gate. After the driver
  implements a numbered plan task, the counterpart model independently reviews
  the uncommitted diff and must return `APPROVED` before the task can be marked
  complete. Hunts hollow shells (stubs/TODO/mock) and hallucinated APIs.
- `hooks/gate-enforce.py` — deterministic enforcement (Claude Code PostToolUse
  hook + standalone git pre-commit mode).
- `install.sh` — installs both skills + the enforcement hook into a target
  project for Claude Code and/or Codex.
- Generic verdict marker `GATE_VERDICT` and configurable plans directory.

### Changed

- Codex reviewer model defaults to `auto`, so the scripts inherit the local Codex
  CLI config instead of shipping a hardcoded model id.

### Fixed

- `gate-enforce.py` now fails closed when explicit CLI mode receives a missing
  `PROGRESS.md` path.
- `install.sh` no longer removes existing non-symlink skill or hook paths unless
  `--force` is passed.

### Community

- Added contribution guide, security policy, CODEOWNERS, pull request template,
  and issue templates for public collaboration.
- Added CODEX (OpenAI Codex) to the README contributors section as an AI coding
  collaborator.
