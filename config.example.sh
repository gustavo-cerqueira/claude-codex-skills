#!/usr/bin/env bash
# config.example.sh — pre-set the counterpart models/behavior for the skills.
#
# Usage:  cp config.example.sh config.local   # *.local is git-ignored
#         # edit, then:  source config.local   before running the skills,
#         # or paste the lines you want into your shell profile.
#
# Every value has a sensible default; you only need to set what you want to change.
# Each *_MODEL accepts: a concrete model/alias (pin), or "auto" (defer to the CLI
# default). The Claude default "opus" is an alias that always resolves to the
# latest Opus. The Codex default here is "auto" because the Codex CLI has no
# "latest" alias; set a concrete model id below when you need pinned reviews.

# ── claude-codex-plan (collaborative planning) ──────────────────────────────
export COLLAB_CODEX_MODEL="auto"      # or a concrete Codex model id
export COLLAB_CODEX_EFFORT="xhigh"    # or "auto"
export COLLAB_CLAUDE_MODEL="opus"     # alias -> latest Opus; or "sonnet"/"auto"/full id
export COLLAB_PLANS_DIR="plans"

# ── codex-gate (per-task validation gate) ───────────────────────────────────
export GATE_CODEX_MODEL="auto"        # or a concrete Codex model id
export GATE_CODEX_EFFORT="xhigh"      # or "auto"
export GATE_CLAUDE_MODEL="opus"       # alias -> latest Opus; or "sonnet"/"auto"/full id
export GATE_PLANS_DIR="plans"
export GATE_TIMEOUT="600"             # seconds per review
export GATE_DIFF_CAP="200000"         # max diff chars sent to the reviewer

# Tip: to always use each CLI's own configured default (never pin), set every
# *_MODEL/*_EFFORT above to "auto".
