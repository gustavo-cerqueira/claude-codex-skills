# Examples

These illustrate the artifacts the skills generate at runtime. (Real runs write
under `plans/<slug>/`, which is git-ignored — these samples are inlined here.)

## `claude-codex-plan` — a debate folder

```
plans/add-rate-limiting/
├── 01_plan.md                 # driver's initial plan
├── 02_reviewer_replica.md     # counterpart's adversarial critique (read-only)
├── 03_driver_refinement.md    # driver answers the critique
├── 04_reviewer_treplica.md    # counterpart's final review (read-only)
├── 05_final_consensus.md      # the debated, agreed plan
└── 06_execution_prompt.md     # paste into the counterpart CLI to execute
```

## `codex-gate` — a review file

`plans/add-rate-limiting/codex-gate/1.1.md` (written by the reviewer; the last
line is what the enforcement hook checks):

```markdown
<!-- gate | task=1.1 reviewer=codex repo=/path/to/repo | 2026-06-16T20:00:00Z -->

Per-criterion review:

- AC1 (token bucket per IP): PASS — src/middleware/rate-limit.ts:14 implements ...
- AC2 (429 + Retry-After): PASS — src/middleware/rate-limit.ts:38 sets header ...
- Subtask 1.1.a (tests): PASS — test/rate-limit.spec.ts exercises burst + refill

### Structured verdict

{ "verdict": "APPROVED", "blockers": [], "summary": "All criteria met with real, tested logic." }

GATE_VERDICT: APPROVED
```

## `codex-gate` — the verdict ledger

`plans/add-rate-limiting/VERDICTS.md` (append-only):

```markdown
# Cross-Model Gate Verdict Ledger — add-rate-limiting

| timestamp (UTC)      | task | verdict           | reviewer/model      | review file       |
| -------------------- | ---- | ----------------- | ------------------- | ----------------- |
| 2026-06-16T19:40:00Z | 1.1  | CHANGES_REQUESTED | codex:gpt-5.5/xhigh | codex-gate/1.1.md |
| 2026-06-16T20:00:00Z | 1.1  | APPROVED          | codex:gpt-5.5/xhigh | codex-gate/1.1.md |
```

## `PROGRESS.md` — gate-aware checkboxes

A task can only be `[x]` once its review is APPROVED. Non-code tasks opt out with
an explicit `Gate: N/A` marker:

```markdown
## Phase 1

- [x] **1.1 Implement rate limiting** — token bucket + 429
- [ ] **1.2 Add metrics**
- [x] **1.3 Create feature branch** (Gate: N/A) — non-code setup
```
