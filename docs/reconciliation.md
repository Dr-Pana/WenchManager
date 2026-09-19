# Reconciliation of recovered local work and the playable-night milestone

## Provenance

- Recovered local version: `f159530463817c8496444aca87ff664c50acc918`
  on `recovery/latest-local`.
- Previously tested milestone: `bc74b57527bae418b7a59fb267a313c645e5be40`
  on `codex/one-manageable-night` (PR #1).
- Shared starting point: `f038db0fac2f129c748ca8c0d2f95811e32c8e4b`.
- Integrated branch: `codex/reconcile-latest-local`.

This branch is intended to replace PR #1 as the candidate for future merging into
Main. Neither source branch is rewritten. All original portrait PNGs and import
metadata are retained unchanged. The recovered design document is preserved in
`docs/recovered_design_archive.md`, and `Issues.md` is retained unchanged as history.

## Decisions

| Area | Reconciled behavior |
| --- | --- |
| Customer arrival | Keep recovered sequential arrivals and manual portrait assignment. Add explicit admission/assignment phases so no callback can finish an hour prematurely. |
| Portrait selector | Keep all three portraits, availability feedback and component code. Place it inside the main layout; portrait textures do not intercept button clicks. |
| Table indicators | Keep the recovered scene and colors. Integrate one indicator into each detailed table panel; use stable numeric slot IDs rather than parsing display text. |
| Table 2 issue | Regressions verify initials update immediately on selection, including Table 2. |
| Assignment freeze | Valid selection returns to admissions, then table processing. Rejected arrivals drain normally; an unavailable roster produces unserved tables rather than an impossible selection prompt. |
| Lifecycle | Keep the milestone's guarded turns, unique visits, one timer, safe restarts, one-time closing and archived summaries. |
| Staffing | Keep manual arrival selection plus the milestone's between-hour reassignment, workload display, exhaustion and recovery. |
| Accounting | Preserve the recovered transaction behavior and 10–30% tips rather than applying the old branch's refund interpretation. Choice identity still prevents duplicate transactions. |
| Narration | Keep recovered resource colors plus explanatory event outcomes and RNG separation. |
| Summary | Keep the previously approved summary fixes. The historical hold in Issues.md predates that milestone. |

## Validation

Godot 4.5 stable source import and regression suites pass:

- 730 simulation checks: phases, choice/assignment identity, slot reuse, queues,
  unavailable roster, recovery, history, and 30 reproducible nights with replay.
- 56 actual-scene UI checks: timer/skip playback, portrait signals, Table 2 initials,
  assignment continuation, restart at a portrait prompt, dropdowns, layout bounds,
  empty narration templates and a complete eight-hour night.
- Linux release export with matching 4.5 stable templates: built successfully.
- Both suites also pass against the packaged Linux executable: 730 + 56 checks.
  Original portrait resources and phrasebook load from the packaged project.
- No portrait image or import metadata changes relative to the recovery branch.
- `git diff --check` is clean.

The test driver chooses the available staff member with the smallest workload and
ignores optional interventions. Its baseline met the provisional goal in 4/30
seeded nights. Human playtesting is still required for balance and graphical
appearance; headless UI tests check behavior and layout bounds, not rendered pixels.
