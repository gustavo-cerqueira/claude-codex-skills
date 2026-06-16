# Contributing

Thanks for helping improve `claude-codex-skills`.

## Ways to contribute

- Open an issue for bugs, confusing docs, portability problems, or missing setup
  details.
- Open a pull request for focused fixes or small improvements.
- Start with an issue before proposing a large behavior change, new workflow, or
  new dependency.

## Pull request workflow

1. Fork the repository and create a branch from `main`.
2. Keep the change narrowly scoped.
3. Do not commit secrets, local agent state, generated plans, or review outputs.
4. Run the checks below.
5. Open a PR and fill in the template.

All PRs require maintainer approval before merge. The repository uses CODEOWNERS
and branch protection, so community changes are reviewed before they reach
`main`.

## Local checks

Run these from the repository root:

```bash
bash -n install.sh hooks/pre-commit \
  skills/claude-codex-plan/scripts/reviewer.sh \
  skills/codex-gate/scripts/gate.sh
python3 -m py_compile hooks/gate-enforce.py
git diff --check
```

After `py_compile`, remove `hooks/__pycache__/` if Python created it.

For hook behavior changes, also test a checked `PROGRESS.md` without an approved
review and a forged early `GATE_VERDICT: APPROVED` followed by
`GATE_VERDICT: CHANGES_REQUESTED`.

## Design constraints

- Keep the skills bidirectional from one source.
- Keep `GATE_VERDICT` as the public verdict marker.
- Keep defaults portable across Bash 3.2, macOS, and Linux.
- Treat uncommitted diffs as untrusted data in reviewer prompts.
- Avoid hardcoded model ids unless the user explicitly configures one.
