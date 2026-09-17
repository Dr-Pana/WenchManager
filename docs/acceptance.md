# One manageable night — acceptance

Run `python3 tests/run_checks.py --godot godot` before playtesting. Automated tests
cover state, inputs, scene signals and layout bounds in headless Godot. They do not
replace visual checks on the target desktop.

## Manual desktop checks

- Import in Godot 4.5 and play. No script errors or missing HUD labels.
- Check the 1152×900 reference viewport, then resize the window. Staff, six table
  panels, resources, log and action buttons should remain visible and legible.
- Advance until customers arrive. Select a staff portrait for each arriving group.
  Verify Table 2 shows the selected staff initials immediately and service resumes.
- Observe the six colored indicators and original portrait art. Observe assignments and use a dropdown between
  hours. Only that visit changes staff; workload counts update immediately.
- Watch a staff member reach zero stamina, become unavailable and recover three
  hours later. A previously uncovered table should regain coverage.
- Read a service event and identify its success/failure and resulting state changes.
- Resolve a crisis; repeated clicking must not apply the same decision twice.
- Restart while narration is active, at a pending portrait assignment, at a pending choice, and after closing.
  No old choices or narration should appear in the new night.
- Finish eight hours. Closing results include departed visits and show whether the
  service objective was met. Further advancement is disabled.
- Repeat these checks using the Linux export, especially phrasebook loading.

## Balance review

The service objective is provisional. Record the seed when running a controlled
simulation (`start_new_night(seed)`) and the staffing decisions used. Compare
purposeful reassignment against default assignments before changing thresholds.
No claim is made that the current roster, goal or recovery duration is final.

## Recovered workflow regression

When a guest enters Table 2, select Mimi's portrait. The indicator should show
"Mim" immediately. Let playback finish: the next arrival or service update must
appear without another Next Hour click. Repeat with multiple arrivals, then
restart while the portrait prompt is open. No old assignment may carry over.
