---
active: false
chain_started_at: null
continuation_task_id: null
merge_detection_task_id: null
root_task_id: null
---

# Harmonize Run Lock

Ensures at most one **root** `/harmonize` chain runs at a time (merge-detection serial pass plus
`post-merge-dispatch` and its dispatch wave). The harmonize master agent owns this file.

`post-merge-dispatch` does **not** acquire the lock again; it **releases** the lock when the chain
finishes **§9**. Standalone **`merge-detection`** and **`resume`** passes acquire and release on the
same agent instance.

## Stale locks

If `active` is true but every stored task id is terminal or unknown, or `chain_started_at` is older
than **6 hours** when `TaskGet` / `TaskList` are unavailable, the next pass may overwrite the lock.

## Entry schema (when active)

| Field | Meaning |
|-------|---------|
| `root_task_id` | `TaskCreate` id for this harmonize master pass (root `run`, or standalone merge-detection / resume) |
| `merge_detection_task_id` | Background `plan-orchestrator` merge-detection task, once spawned |
| `continuation_task_id` | Nested `harmonize` `post-merge-dispatch` task, once spawned (root `run` only) |
