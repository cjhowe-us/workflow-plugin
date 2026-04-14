---
id: PLAN-{domain}-{topic}
name: {Plan Name}
status: not_started
parent: null
children: []
execution_mode: sequential
dependencies: []
design_documents:
  - docs/design/{domain}/{group}.md
features: []
requirements: []
test_cases: []
worktree_branch: plan/{domain}-{topic}
progress_file: docs/plans/progress/PLAN-{domain}-{topic}.md
---

# {Plan Name} Implementation Plan

## SDLC links

- **Progress:** [../progress/PLAN-{domain}-{topic}.md](../progress/PLAN-{domain}-{topic}.md)
- **Phase rollup:** [../progress/phase-plan.md](../progress/phase-plan.md)
- **Plan index:** [../index.md](../index.md)

> **Plan ID:** `PLAN-{domain}-{topic}`
>
> **Instructions for agents working on this plan:** Before any action, load the `harmonize` skill
> and read the progress file at `docs/plans/progress/PLAN-{domain}-{topic}.md`. Do not duplicate
> completed steps. Update the progress file as each step finishes. All code changes happen in
> the worktree at `../harmonius-worktrees/PLAN-{domain}-{topic}/`, never in the main checkout.

## Execution Instructions

1. Read the progress file. If `status != not_started`, resume from the first unchecked item.
2. If `status == not_started`:
   - `git worktree add ../harmonius-worktrees/PLAN-{domain}-{topic} -b plan/{domain}-{topic}`
   - `cd ../harmonius-worktrees/PLAN-{domain}-{topic}`
   - `gh pr create --draft --base main --head plan/{domain}-{topic} --title "[PLAN-{domain}-{topic}] {Plan Name}"`
   - Update progress: `status: started`, `worktree_path`, `pr_url`, `pr_number`, `started_at`
3. For each task row in Task Breakdown, in order:
   - Spawn `test-writer` agent for the TC entries (red)
   - Run `cargo test` in the worktree — tests must FAIL
   - Commit red tests with message `red: TC-X.Y.Z (short description)`
   - Spawn `implementer` agent with the test + design API section (green)
   - Run `cargo test` — tests must PASS
   - Run `cargo clippy -- -D warnings` and fix any warnings
   - Run `rumdl check .` if markdown files changed
   - Commit green implementation with message `green: TC-X.Y.Z`
   - `git push` to the draft PR
   - Update progress checklist and event log
4. After all tasks: run final verification (`cargo test --workspace`, `cargo clippy --workspace
   -- -D warnings`, `rumdl check .`)
5. Update progress: `status: code_complete`
6. Return to the orchestrator. The orchestrator will dispatch `pr-reviewer` next.

## Source Documents

| Document | Path |
|----------|------|
| Design | [docs/design/{domain}/{group}.md](../../design/{domain}/{group}.md) |
| Integration | [docs/design/integration/{a}-{b}.md](../../design/integration/{a}-{b}.md) |
| Test Cases | [docs/design/{domain}/{group}-test-cases.md](../../design/{domain}/{group}-test-cases.md) |
| Features | [docs/features/{domain}/{topic}.md](../../features/{domain}/{topic}.md) |
| Requirements | [docs/requirements/{domain}/{topic}.md](../../requirements/{domain}/{topic}.md) |
| Progress | [docs/plans/progress/PLAN-{domain}-{topic}.md](../progress/PLAN-{domain}-{topic}.md) |

## Scope

{What is being implemented. Reference specific F-X.Y.Z feature IDs and R-X.Y.Z requirement IDs
from the design.}

### In Scope

- {Feature or capability being implemented}
- {Another feature}

### Out of Scope

- {What is explicitly NOT part of this plan}
- {Deferred to a future plan — link the future plan ID}

## Crate Structure

Crates this plan creates or modifies:

| Crate | Purpose | Dependencies |
|-------|---------|--------------|
| harmonius_{name} | {purpose} | {deps} |

## Task Breakdown

Ordered by implementation sequence. Each task produces a testable increment. Each task row maps
to specific TC entries written first as failing tests.

### Phase 1: Foundation

| # | Task | Est | Requirement | Test |
|---|------|-----|-------------|------|
| 1 | {task description} | {hours} | R-X.Y.Z | TC-X.Y.Z.1 |
| 2 | {task description} | {hours} | R-X.Y.Z | TC-X.Y.Z.2 |

### Phase 2: Core Features

| # | Task | Est | Requirement | Test |
|---|------|-----|-------------|------|
| 3 | {task description} | {hours} | R-X.Y.Z | TC-X.Y.Z.3 |
| 4 | {task description} | {hours} | R-X.Y.Z | TC-X.Y.Z.4 |

### Phase 3: Integration

| # | Task | Est | Requirement | Test |
|---|------|-----|-------------|------|
| 5 | {integration task} | {hours} | IR-X.Y.Z | TC-X.Y.Z.I1 |

### Phase 4: Polish and Optimization

| # | Task | Est | Requirement | Test |
|---|------|-----|-------------|------|
| 6 | {optimization task} | {hours} | R-X.Y.Za | TC-X.Y.Z.B1 |

## Dependencies

The `dependencies` field in frontmatter is the authoritative machine-readable list for the
orchestrator. This section narrates WHY each dependency exists so human reviewers can verify.

### Blocking (must be merged before this plan starts)

- `PLAN-{id}` — {why this must complete first, e.g., "provides the Entity type used here"}

### Parallel (can proceed alongside)

- `PLAN-{id}` — {why this is independent}

### Downstream (blocked by this plan)

- `PLAN-{id}` — {why it depends on this — types, traits, or functions defined here}

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| {risk description} | H / M / L | {mitigation strategy} |

## Integration Points

For each system this plan touches beyond the primary design, document the boundary:

| System | Data Flow | Phase |
|--------|-----------|-------|
| {other system} | {what data crosses} | {game loop phase} |

## Test Strategy

### Unit Tests (Phase 1-2)

- Write failing tests from TC-X.Y.Z entries BEFORE implementing
- Each task row maps to specific TC entries in the companion test-cases file
- Run `cargo test` after each task — all new tests green before moving on

### Integration Tests (Phase 3)

- Write failing integration tests from TC-X.Y.Z.I entries
- Test cross-system boundaries identified in the integration design
- Run with real dependencies (no mocking — follow the project testing policy)

### Benchmarks (Phase 4)

- Run benchmarks from TC-X.Y.Z.B entries
- Verify numeric targets from requirements
- Compare against baseline (if one exists)

## Verification

How to verify the implementation is complete:

1. All TC-X.Y.Z unit tests pass
2. All TC-X.Y.Z.I integration tests pass
3. All TC-X.Y.Z.B benchmarks meet numeric targets
4. `cargo clippy --workspace -- -D warnings` — zero warnings
5. `rumdl check .` — zero lint errors on docs
6. Design document updated with any deviations from the original spec
7. Progress file `status: code_complete` set by the plan-implementer
