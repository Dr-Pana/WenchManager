# Live dashboard

Built on the reconciled version at `38a0ee81` on a separate `codex/live-dashboard`
branch. No simulation rules, configuration values or portrait assets are modified.

## Player-facing changes

- Persistent clock shows the current service interval and hour number during a
  turn, and the actual boundary time between turns and at closing.
- Overview shows occupied/total tables, guests, unserved tables and completed visits.
- Staff panels show current/max stamina, availability, recovery hours, assigned
  table numbers, stats and accumulated tips.
- Six persistent table panels show occupied/empty status, guests, assigned staff,
  satisfaction and rowdiness. Existing indicators and reassignment controls remain.
- Assignment/decision targets are named on screen. No event log is needed to know
  which table needs input.
- Closing results display in a dedicated panel, even with history hidden.
- Event history is opt-in, capped at 160 recent entries and independent of pacing.
- Continue now advances the current automatic step; Next Hour starts a new hour.
- Main controls sit in a fixed footer; the dashboard body scrolls when necessary.

The panels update in place, preserving control identity and avoiding per-update
rebuilding of the staff and table interfaces. Restart clears old results/history
and refreshes the same controls.

## Validation

Godot 4.5 stable: 730 existing simulation checks and 69 scene/UI checks pass.
The UI suite verifies immediate opening, live stamina/occupancy updates, persistent
node identity, assignment/decision context, portrait flow, timer/skip continuation,
optional history, bounded history, closing results and restart. Layout bounds are
checked with history open and three choices; primary controls stay in the viewport.

This pass was tested headlessly. A visual desktop playtest is still needed for
readability, scrolling, focus and window resizing. No native export was rebuilt
for this UI pass; the export preset and resource dependencies are unchanged.

## Quick playtest

1. Start a new night without opening history. Confirm the clock and all six slots.
2. Advance, assign staff through portraits, and watch occupied counts/initials change.
3. At an hour boundary, verify stamina and recovery indicators; change an assignment.
4. Resolve a decision using the named table and on-screen buttons.
5. Toggle history during play. It should not change outcomes or delay input.
6. Finish the night, read results without history, then restart.
