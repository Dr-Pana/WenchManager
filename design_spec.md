# Wench Manager — One manageable night (v0.3)

This document describes the implemented milestone. The original long-term design
is preserved in `docs/design_spec_v0.2_archive.md`; its implementation claims are
historical, not a description of this build.

## Scope and player loop

A text-based fantasy tavern management game in Godot 4.5, with three fixed staff
members and six reusable table slots. Each night has eight service intervals,
5pm–1am. Start empty, advance an hour, read events and resolve crises, adjust
assignments between hours, then finish with results and restart.

The provisional service goal is at least three completed visits and average
departure satisfaction >= 0 across **all** departed visits, including bounced
visits. Bouncing a difficult group therefore does not erase it from the score.
A night with no customers never meets the goal. Sales and staff tips are separate.
This is a service objective, not a campaign economy or a bankruptcy system.

## Structure

- `Main.tscn`: one scene; log, controls, staff dashboard, six table panels, HUD.
- `main.gd`: UI controller, one narration timer, choices and reassignment.
- `HUD.gd`: inventory/gold labels driven by simulation signals.
- `scripts/simulation.gd`: state transitions, visits, staffing, rules and results.
- `scripts/game_config.gd`: rule constants and provisional balance settings.
- `phrasebook.md`: optional local narration templates, included explicitly in exports.
- `tests/`: dependency-free simulation and scene regression checks.

## Turn contract

`Simulation.Phase` is the authority:

- `BETWEEN_HOURS`: assignments and `advance_hour()` are allowed.
- `PROCESSING`: only `process_next_table()` advances the active hour.
- `AWAITING_CHOICE`: only an exact pending choice ID may resolve the decision.
- `CLOSED`: gameplay mutations are blocked until `start_new_night()`.

`hour` counts completed intervals. `hour_in_progress` is a derived compatibility
property, not another mutable state flag. Hour completion and closing each occur
once. Invalid/stale actions are no-ops that preserve the current choices.

Each hour admits customers, refreshes coverage, snapshots staff workloads, and
processes a shuffled list of visits. At the boundary, departures are archived,
staff fatigue/recovery is updated, time advances and coverage is refreshed.

Each result contains `log_lines`, `choices`, and `phrasebook_updates`. The UI
controls presentation but never determines whether an hour exists or has ended.
One timer connection handles playback. Restart clears its queue and stops the
timer. "Show next line" advances narration without advancing an extra hour.
Missing templates do not block progress; mechanical outcome lines still display.

## Identity and history

- Slot IDs 1–6 represent the physical table panels. Arrivals use the first free slot.
- `visit_id` increases for each admitted customer group within a night.
- Choices include the night serial, hour, visit ID and action, so a queued choice
  from an earlier night cannot target a reused slot.
- Departures pass through one archive function; records are copied into
  `visit_history` before removal. Duplicate removals have no effect.
- `active_wench` on the visit is authoritative; staff `assigned_tables` is rebuilt
  from live visits and contains integer slot IDs.
- Summary calculation is read-only and includes departed visits and their peak
  rowdiness. Tips are settled only on departure, never during summary display.

## Staffing

The fixed roster is Lysa, Brakka and Mimi. New/uncovered visits receive an
available staff member with the fewest active tables. Existing valid assignments
are preserved. The player can select a different available staff member through
a table's dropdown **between hours**. Empty slots and unavailable staff cannot be
selected. Reassignment changes no time, stock or tips.

Staff lose `BASE_STAMINA_DRAIN + (table_count - 1) *
OVERWORK_STAMINA_DRAIN_PER_TABLE` once per completed hour, based on the workload
snapshot. This includes groups that depart or are bounced during that hour.
Serving the final hour completes before its fatigue is applied.

At zero stamina, staff become exhausted for three subsequent service intervals.
They cannot serve or be assigned while exhausted. At the end of the third recovery
interval, availability and full stamina return. Idle available staff recover one
stamina per hour up to their maximum. Backup coverage is load-balanced from the
currently available roster rather than stored in stale backup lists.

Unserved tables receive the configured satisfaction/rowdiness penalties and do
not complete service transactions. Their event chance multiplier is applied when
the final event chance is computed, then clamped to [0, 1]. Previously unserved
visits are reconsidered when staff become available.

## Events and accounting

The existing event set, arrivals, resource prices, crisis thresholds and stock
values remain. Service requests and spill recovery use the existing `service`
stat; social events use `charm`. Fatigue, race compatibility and workload modifiers
still apply. Outcomes and net satisfaction/rowdiness changes are shown explicitly.

The free-round intervention comps the round already served that hour: refund its
payment once, do not deduct inventory again, then apply the existing satisfaction
and rowdiness effects. If nothing was served, it has no effect. Tips cannot be
negative. Consuming exactly the remaining stock without a shortfall is not treated
as a failed order.

A dedicated simulation RNG accepts an optional seed for reproducible tests.
Narration has a separate RNG, so changing/removing templates does not change rules
or customer outcomes for a given seed and set of decisions.

## Deliberately deferred

Hiring, supply purchasing, promotion duties, trait effects, table meltdowns,
socializing/invitation mechanics, campaign persistence, portraits and AI narration
are future work. Group-specific event weights still use legacy archetype keys;
generated groups currently use the default event distribution. The legacy
`patience`, `resource_drain_rate` and `attitude_modifiers` fields are not active
systems. No extra systems should be inferred from their presence.

The AI design remains: game rules decide outcomes; optional generation may later
supply flavor. This build works offline and makes no API calls.
