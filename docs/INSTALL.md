# Install guide

## Prerequisites

- **Claude Code CLI** (`claude`) signed in with an active subscription/API key.
- **OpenAI Codex CLI** (`codex`) signed in with an active subscription/API key.
- `bash`, `git`, `python3` on `PATH`.

Verify:

```bash
claude --version && codex --version && python3 --version
```

## Quick install (recommended)

```bash
git clone https://github.com/gustavo-cerqueira/claude-codex-skills.git
cd claude-codex-skills
./install.sh --target /path/to/your/project --mode both
```

By default the installer **symlinks** the skills into the target so a later
`git pull` in this repo updates them everywhere. Use `--copy` for a frozen,
self-contained copy.

## Manual install

### 1. Claude Code

```bash
# From the repo root, with PROJECT=/path/to/your/project
mkdir -p "$PROJECT/.claude/skills" "$PROJECT/.claude/hooks"
ln -s "$PWD/skills/claude-codex-plan" "$PROJECT/.claude/skills/claude-codex-plan"
ln -s "$PWD/skills/codex-gate"        "$PROJECT/.claude/skills/codex-gate"
ln -s "$PWD/hooks/gate-enforce.py"    "$PROJECT/.claude/hooks/gate-enforce.py"
```

Register the enforcement hook in `$PROJECT/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/gate-enforce.py"
          }
        ]
      }
    ]
  }
}
```

If `settings.json` already has a `PostToolUse` array, append the matcher object to
it rather than replacing the file.

### 2. OpenAI Codex

Codex discovers skills under `.agents/skills/`. Point `.agents` at `.claude` so
both CLIs share one skill folder:

```bash
cd "$PROJECT" && ln -s .claude .agents
```

For deterministic enforcement when Codex is the driver (the PostToolUse hook is
Claude-Code-specific), install the git pre-commit hook. It needs
`gate-enforce.py` to be discoverable — the hook auto-finds it next to itself or
at `<repo>/.claude/hooks/gate-enforce.py` (installed in step 1), or you can point
`GATE_ENFORCE` at it explicitly:

```bash
cp "$REPO/hooks/pre-commit" "$PROJECT/.git/hooks/pre-commit"
chmod +x "$PROJECT/.git/hooks/pre-commit"
# Ensure gate-enforce.py is reachable (already true if you did step 1):
#   ls "$PROJECT/.claude/hooks/gate-enforce.py"
# or: export GATE_ENFORCE="$REPO/hooks/gate-enforce.py"
```

The pre-commit hook blocks any commit whose **staged** `PROGRESS.md` marks a task
`[x]` without an `APPROVED` review (or a `(Gate: N/A)` exemption). It reads the
staged content, so reverting a checkbox in the working tree after `git add`
cannot sneak a violation through. `install.sh --mode codex|both` installs this
hook for you (without overwriting an existing `pre-commit`).

## Verify the install

```bash
# Claude Code: the skills should appear in /skills or be invocable:
#   /claude-codex-plan "smoke test"
#
# Codex: confirm the symlink resolves
ls -l "$PROJECT/.agents"          # -> .claude
ls "$PROJECT/.agents/skills"      # -> claude-codex-plan  codex-gate

# Enforcement hook (CLI mode) sanity check:
tmp="$(mktemp -d "${TMPDIR:-/tmp}/gate-smoke.XXXXXX")"
mkdir -p "$tmp/plans/smoke"
printf '%s\n' '- [x] **1.1 Smoke task** — should be blocked without review' > "$tmp/plans/smoke/PROGRESS.md"
python3 "$REPO/hooks/gate-enforce.py" "$tmp/plans/smoke/PROGRESS.md"; echo "exit=$?"   # exit=1
rm -rf "$tmp"
```

## Configuration

See the table in the [README](../README.md#configuration). All defaults work out
of the box; override via environment variables when you need a different model,
plans directory, or timeout.

## Uninstall

Remove the symlinks/copies and the `PostToolUse` entry from `settings.json`:

```bash
rm "$PROJECT/.claude/skills/claude-codex-plan" \
   "$PROJECT/.claude/skills/codex-gate" \
   "$PROJECT/.claude/hooks/gate-enforce.py"
# Optionally: rm "$PROJECT/.agents"  and  "$PROJECT/.git/hooks/pre-commit"
```
