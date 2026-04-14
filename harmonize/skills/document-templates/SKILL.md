---
name: document-templates
description: >
  Templates for creating design documents, integration designs,
  features, requirements, user stories, and test cases in the
  Harmonius project. Use this skill when creating any new document
  from a template, or when reviewing whether an existing document
  follows the required structure.
---

# Document Templates

All templates are in the `templates/` directory alongside this skill. Read the appropriate template
file and use it as the starting point for the new document.

## Available Templates

| Template | File | Use When |
|----------|------|----------|
| Design document | `templates/design-document.md` | New subsystem design |
| Integration design | `templates/integration-design.md` | Feature crosses 2+ systems |
| Feature | `templates/feature.md` | New feature definition |
| Requirement | `templates/requirement.md` | New requirement |
| User story | `templates/user-story.md` | New user story |
| Test cases | `templates/test-cases.md` | Companion test file |
| Implementation plan | `templates/implementation-plan.md` | Task breakdown driven by harmonize |
| Plan progress | `templates/plan-progress.md` | Progress tracking for a harmonize plan |
| Phase progress | `templates/phase-progress.md` | Per-phase rollup (specify / design / plan / release) |
| Locks registry | `templates/locks.md` | Worktree claims (`branch`, path, phase, reason) |
| In-flight registry | `templates/in-flight.md` | Running background tasks |
| Worktree state | `templates/worktree-state.json` | Live background tasks; Claude `SubagentStop` hook (`bash`/`jq`) updates |
| Harmonize run lock | `templates/harmonize-run-lock.md` | Serialize root `/harmonize` chains |
| Release plan | `templates/release-plan.md` | Release checklist and rollout |

## How to Use

1. Read the template file for the document type needed
2. Copy the template content to the target file location
3. Fill in all placeholder fields (marked with `{curly braces}`)
4. Run `rumdl fmt` on the completed document
5. Verify all sections are filled — do not skip any

## File Locations

| Document Type | Target Directory |
|--------------|-----------------|
| Design | `docs/design/{domain}/{group}.md` |
| Integration | `docs/design/integration/{a}-{b}.md` |
| Feature | `docs/features/{domain}/{topic}.md` |
| Requirement | `docs/requirements/{domain}/{topic}.md` |
| User story | `docs/user-stories/{domain}/{topic}.md` |
| Test cases | `docs/design/{domain}/{group}-test-cases.md` |
| Implementation plan | `docs/plans/{subsystem}/{topic}.md` |
| Plan progress | `docs/plans/progress/PLAN-{subsystem}-{topic}.md` |
| Root plan | `docs/plans/index.md` |

## When to Use Integration Design

Create an integration design when:

- A feature requires changes in 2+ design documents
- Data flows from one subsystem to another at runtime
- Two systems must agree on types, timing, or ordering
- A user story spans multiple game loop phases

Examples from this project:

- Animation ↔ Physics (ragdoll, foot IK, character controller)
- AI ↔ Animation (AnimationParams, MovementState)
- Audio ↔ Spatial (BVH queries for sound occlusion)
- Rendering ↔ Procedural (async compute → render graph)
- Networking ↔ Physics (determinism, rollback, replication)
- ECS ↔ Plugins (middleman .dylib, codegen types)

## Required Considerations Checklist

Every design document MUST address ALL of the following:

**Architecture:**

- [ ] Uses custom job system (crossbeam-deque), not Rayon/Tokio
- [ ] No async/await in engine/editor/runtime (permitted in backend)
- [ ] Platform-native I/O (io_uring, IOCP, GCD)
- [ ] ECS-primary where applicable
- [ ] Zero reflection — codegen generates all type metadata
- [ ] Static dispatch preferred — dyn justified if used
- [ ] Plugins are data — middleman .dylib for codegen'd types
- [ ] Codegen preferred for all dynamic editor content

**Rendering:**

- [ ] GPU-driven where applicable
- [ ] Render layers (u32 bitmask) supported
- [ ] All passes are render graph nodes
- [ ] Render thread: only block on swapchain acquire
- [ ] Per-frame resources ring-buffered

**Physics:**

- [ ] Physics-private BVH (not shared BVH)
- [ ] Collision layers (u32 bitmask) supported
- [ ] Fixed timestep in FixedUpdate phase
- [ ] Deterministic (sorted iterations, no HashMap on hot path)

**Spatial:**

- [ ] Shared BVH for AI/gameplay/audio queries
- [ ] Grid for networking relevancy
- [ ] GPU handles rendering visibility

**2D/2.5D:**

- [ ] Works for 2D, 2.5D, and 3D games
- [ ] 2D transforms (Transform2D) considered
- [ ] 2D physics shapes considered
- [ ] 2D rendering (sprites, tilemaps) considered

**Performance:**

- [ ] Bulk sim data in GPU buffers, not ECS entities
- [ ] SmallVec for small inline allocations
- [ ] Per-thread arenas for hot-path allocations
- [ ] No HashMap on deterministic hot paths

**Serialization:**

- [ ] rkyv for zero-copy binary assets
- [ ] No bevy_reflect, no TypeRegistry, no dyn Reflect
- [ ] Asset handles via Handle pattern

**Testing:**

- [ ] Companion test cases file exists
- [ ] Every requirement has at least one test
- [ ] Benchmarks with specific numeric targets
- [ ] No mocking — real objects, fakes only when necessary

**Integration:**

- [ ] Game loop phase identified
- [ ] Input/output data flows documented
- [ ] Frame-boundary handoff points specified

**Error and recovery:**

- [ ] Failure modes enumerated
- [ ] Recovery strategy per failure mode
- [ ] Mid-frame failure behavior defined

**Editor UX:**

- [ ] Editor interaction flows described
- [ ] Visual affordances specified
- [ ] No-code workflow validated

**Onboarding:**

- [ ] Mental model documented
- [ ] Terminology mapping table
- [ ] First-use workflow described

**Benchmarking:**

- [ ] Reference scenario defined
- [ ] Profiling methodology specified
- [ ] Regression targets with numeric thresholds

**Documentation:**

- [ ] Algorithm references with direct URLs
- [ ] 100 char line limit (tables exempt)
- [ ] Mermaid diagrams only (no ASCII art)
- [ ] Sentence case headings

## Integration Design Checklist

- [ ] All shared types defined in exactly ONE system
- [ ] Data flow direction clear (who writes, who reads)
- [ ] Game loop phase ordering specified
- [ ] No circular dependencies between systems
- [ ] Failure modes documented with recovery strategy
- [ ] ECS components for cross-system data (not globals)
- [ ] Works in 2D and 3D
- [ ] Platform differences addressed
- [ ] Integration tests cover the boundary

## Development Lifecycle

See the `workflow` skill for the full lifecycle. Templates are used at these stages:

| Stage | Templates Used |
|-------|---------------|
| Ideate | feature, requirement, user-story |
| Design | design-document, integration-design |
| Design review | (feedback appended to design doc) |
| Plan | implementation-plan, plan-progress (via `harmonize` skill) |
| TDD | test-cases |
