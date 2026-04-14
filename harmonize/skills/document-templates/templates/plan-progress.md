---
plan_id: PLAN-{domain}-{topic}
pr_review_status: not_started
status: not_started
started_at: null
last_updated: null
worktree_path: null
branch: null
pr_url: null
pr_number: null
---

# Progress: {Plan Name}

## Cross-links (required)

| Artifact | Link |
|----------|------|
| Implementation plan | [../{subsystem}/{topic}.md](../{subsystem}/{topic}.md) |
| Phase plan rollup | [phase-plan.md](phase-plan.md) |
| Plan tree index | [../index.md](../index.md) |

## Checklist

Mark each item when it completes. Order reflects the typical execution sequence; it is OK to
skip items that do not apply to this plan (e.g., a plan with no integration tests).

- [ ] Worktree created
- [ ] Draft PR opened
- [ ] Design documents read
- [ ] Phase 1: red tests written
- [ ] Phase 1: implementation complete
- [ ] Phase 1: green tests passing
- [ ] Phase 2: red tests written
- [ ] Phase 2: implementation complete
- [ ] Phase 2: green tests passing
- [ ] Phase 3: integration tests written
- [ ] Phase 3: integration tests passing
- [ ] Phase 4: benchmarks meet numeric targets
- [ ] `cargo test --workspace` — all pass
- [ ] `cargo clippy --workspace -- -D warnings` — zero warnings
- [ ] `rumdl check .` — zero lint errors
- [ ] Code complete marker set (status=code_complete)
- [ ] Review findings addressed
- [ ] PR ready for human review (undrafted, status=submitted)
- [ ] Merged by human (detected by orchestrator via gh)

## Event log

Append one line per event using ISO 8601 UTC timestamps. Keep lines short and factual.

- {timestamp} — {event}
