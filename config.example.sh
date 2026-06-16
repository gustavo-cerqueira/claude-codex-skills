#!/usr/bin/env bash
# config.example.sh — pre-set the counterpart models/behavior for the skills.
#
# Usage:  cp config.example.sh config.sh   # (config.sh is git-ignored via *.local? no — add it)
#         # edit, then:  source config.sh   before running the skills,
#         # or paste the lines you want into your shell profile.
#
# Every value has a sensible default; you only need to set what you want to change.
# Each *_MODEL accepts: a concrete model/alias (pin), or "auto" (defer to the CLI
# default). The Claude default "opus" is an alias that always resolves to the
# latest Opus. The Codex CLI has no "latest" alias — pin a version, set it here,
# or use "auto" to inherit ~/.codex/config.toml.

# ── claude-codex-plan (collaborative planning) ──────────────────────────────
export COLLAB_CODEX_MODEL="gpt-5.5"   # or "auto"
export COLLAB_CODEX_EFFORT="xhigh"    # or "auto"
export COLLAB_CLAUDE_MODEL="opus"     # alias -> latest Opus; or "sonnet"/"auto"/full id
export COLLAB_PLANS_DIR="plans"

# ── codex-gate (per-task validation gate) ───────────────────────────────────
export GATE_CODEX_MODEL="gpt-5.5"     # or "auto"
export GATE_CODEX_EFFORT="xhigh"      # or "auto"
export GATE_CLAUDE_MODEL="opus"       # alias -> latest Opus; or "sonnet"/"auto"/full id
export GATE_PLANS_DIR="plans"
export GATE_TIMEOUT="600"             # seconds per review
export GATE_DIFF_CAP="200000"         # max diff chars sent to the reviewer

# Tip: to always use each CLI's own configured default (never pin), set every
# *_MODEL/*_EFFORT above to "auto".
