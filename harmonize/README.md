# harmonize Plugin

A Claude Code plugin that provides a full SDLC supervisor for the Harmonius game engine: feature
ideation, hierarchical design, design review, implementation planning, hierarchical TDD execution,
PR review, and release. Background agents do all file writes and git operations via many small draft
PRs; interactive sub-skills let the user give feedback at any level of the SDLC.

## Dependencies

This plugin requires the companion [`rumdl`](../rumdl) plugin for Markdown linting and
auto-formatting of the documents its agents author. Install `rumdl` first.

## Install

```bash
# Add the marketplace
claude plugin marketplace add cjhowe-us/workflow

# Install rumdl first, then harmonize
claude plugin install rumdl@cjhowe-us-workflow
claude plugin install harmonize@cjhowe-us-workflow
```

## Update

```bash
claude plugin update harmonize@cjhowe-us-workflow
```

## Uninstall

```bash
claude plugin uninstall harmonize
```

## Skills

| Skill | Purpose |
|-------|---------|
| `harmonize` | Master entry — stash gate on `main`, worktree-isolated PRs, merge chain, parallel SDLC |
| `harmonize-specify` | Interactive Phase 1: feature / requirement / user-story ideation |
| `harmonize-design` | Interactive Phase 2: subsystem / interface / component / integration design |
| `harmonize-plan` | Interactive Phase 3a: implementation plan authoring |
| `harmonize-implement` | Interactive Phase 3b: step through or observe TDD |
| `harmonize-review` | Interactive Phase 3c: review a draft PR interactively |
| `harmonize-release` | Interactive Phase 4: cut a release |
| `document-templates` | Templates for every artifact type |
| `rust` | Rust coding standard |
| `hlsl` | HLSL shader coding standard |
| `json` | JSON configuration standard |
| `toml` | TOML configuration standard |
| `yaml` | YAML workflow standard |

The `markdown` skill is provided by the `rumdl` plugin.

## Agents

### Master supervisor

| Agent | Role | Model |
|-------|------|-------|
| `harmonize` | Full SDLC supervisor — reconciles state, dispatches phase orchestrators | opus |

### Phase orchestrators

| Agent | Phase | Role | Model |
|-------|-------|------|-------|
| `specify-orchestrator` | 1 Specify | Dispatches feature / requirement / user-story workers | opus |
| `design-orchestrator` | 2 Design | Dispatches designers + reviewer + reviser | opus |
| `plan-orchestrator` | 3 Plan + TDD | Authors plans, implements, reviews PRs | opus |
| `release-orchestrator` | 4 Release | Coordinates release notes + changelog + tag | opus |

### Phase 1 workers (specify)

| Agent | Role | Model |
|-------|------|-------|
| `feature-author` | Writes a feature file + opens draft PR | opus |
| `requirement-author` | Writes a requirement file + opens draft PR | opus |
| `user-story-author` | Writes a user-story file + opens draft PR | opus |

### Phase 2 workers (design)

| Agent | Role | Model |
|-------|------|-------|
| `subsystem-designer` | Drafts a subsystem design doc + opens draft PR | opus |
| `integration-designer` | Drafts an integration design + opens draft PR | opus |
| `interface-designer` | Drafts the API section of a design + opens draft PR | opus |
| `component-designer` | Drafts internal component details + opens draft PR | opus |
| `design-reviewer` | Reviews a design PR against constraints + posts findings | opus |
| `design-reviser` | Addresses review findings on a design PR | opus |

### Phase 3 workers (plan + TDD + review)

| Agent | Role | Model |
|-------|------|-------|
| `plan-author` | Authors implementation plan files + opens draft PR | opus |
| `plan-implementer` | Worktree + draft PR + TDD loop for one plan | opus |
| `pr-reviewer` | Reviews and undrafts a code-complete PR | opus |
| `test-writer` | Writes failing tests from TC entries | opus |
| `implementer` | Implements code to make tests pass | opus |
| `review-supervisor` | Spawns three focused reviewers in parallel | opus |
| `correctness-reviewer` | Checks code vs design | opus |
| `standards-reviewer` | Checks coding standards | opus |
| `architecture-reviewer` | Checks engine constraints | opus |

### Phase 4 workers (release)

| Agent | Role | Model |
|-------|------|-------|
| `release-notes-author` | Drafts release notes + opens release PR | opus |
| `changelog-updater` | Updates CHANGELOG.md on the release PR | opus |
| `tagger` | Creates annotated git tag after release PR merges | opus |

## Templates

| Template | Path |
|----------|------|
| Design document | `skills/document-templates/templates/design-document.md` |
| Integration design | `skills/document-templates/templates/integration-design.md` |
| Implementation plan | `skills/document-templates/templates/implementation-plan.md` |
| Plan progress | `skills/document-templates/templates/plan-progress.md` |
| Phase progress | `skills/document-templates/templates/phase-progress.md` |
| Locks registry | `skills/document-templates/templates/locks.md` |
| In-flight registry | `skills/document-templates/templates/in-flight.md` |
| Harmonize run lock | `skills/document-templates/templates/harmonize-run-lock.md` |
| Release plan | `skills/document-templates/templates/release-plan.md` |
| Feature | `skills/document-templates/templates/feature.md` |
| Requirement | `skills/document-templates/templates/requirement.md` |
| User story | `skills/document-templates/templates/user-story.md` |
| Test cases | `skills/document-templates/templates/test-cases.md` |

## Lifecycle

```text
Phase 1: Specify   → specify-orchestrator → feature/requirement/user-story-author
Phase 2: Design    → design-orchestrator → subsystem/interface/component/integration-designer
                                         → design-reviewer → design-reviser
Phase 3: Plan+TDD  → plan-orchestrator → plan-author
                                       → plan-implementer → test-writer → implementer
                                       → pr-reviewer → review-supervisor → *-reviewer
Phase 4: Ship      → release-orchestrator → release-notes-author → changelog-updater → tagger
```

The `harmonize` master agent supervises all phases and dispatches phase orchestrators as background
tasks. Interactive sub-skills (`harmonize-specify`, `harmonize-design`,...) claim coarse locks on
`(phase, subsystem)` pairs so the user can give feedback at any level without the background
orchestrator stepping on their work.

## State files

Per-project state lives in the Harmonius repo under `docs/plans/`:

| File | Purpose |
|------|---------|
| `docs/plans/index.md` | Root plan with total topological order |
| `docs/plans/<subsystem>/<topic>.md` | Individual plan files |
| `docs/plans/progress/phase-<name>.md` | Per-phase rollup progress |
| `docs/plans/progress/PLAN-<id>.md` | Per-plan detail progress |
| `docs/plans/locks.md` | Active coarse interactive locks |
| `docs/plans/in-flight.md` | Running background tasks |
| `docs/plans/harmonize-run-lock.md` | At most one root harmonize chain at a time |

## License

Apache-2.0
