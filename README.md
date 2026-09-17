# Wench Manager

A text-based Godot 4.5 tavern management prototype. This branch implements the
**One manageable night** milestone: eight hours, six table slots, three staff,
player reassignment, clear event outcomes and an accurate closing summary.

## Run

Use Godot **4.5 stable**, standard edition. Import `project.godot` and press F6/F5
with `Main.tscn`, or run from the repository root:

```sh
godot --editor --path .
godot --path .
```

The scene uses a 1152 × 900 reference viewport and scales with the window.
No plugins, API keys or external dependencies are required.

- Wait for opening narration or use **Show next line**.
- **Next Hour** begins service. Resolve any choice when it appears.
- Between hours, use each occupied table's dropdown to assign available staff.
- Watch stamina, coverage and satisfaction. Unassigned idle staff recover stamina;
  exhausted staff recover after three hours.
- At 1am the night closes. **New Night** starts a fresh run, including during playback.

The provisional goal is three completed visits with nonnegative average departure
satisfaction, including bounced groups in that average. Balance still needs human
playtesting; the objective and recovery settings are in `scripts/game_config.gd`.

## Verify

Python 3 is only needed for the convenience runner:

```sh
python3 tests/run_checks.py --godot godot
```

Or run each check directly (the editor import must come first on a fresh checkout):

```sh
godot --headless --editor --path . --quit
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_ui.gd
```

The simulation checks cover turn guards, identities, stale choices, one-time
accounting, exhaustion/recovery, archives, objectives and 30 reproducible nights.
The UI checks instantiate the actual scene and exercise timers, restart, selector
signals, choices, layout bounds and completion with no narration templates.

## Export (Linux x86_64)

Install the matching **4.5 stable export templates** through Godot's export-template
manager. From the project root:

```sh
mkdir -p builds
godot --headless --path . --export-release Linux builds/WenchManager.x86_64
./builds/WenchManager.x86_64
```

The Linux preset embeds the project pack and includes `phrasebook.md`. Tests and
design documents are excluded. Builds are ignored by git. A pack-only export can
also be made with `--export-pack Linux builds/WenchManager.pck`.

## Design and limits

See `design_spec.md` for the current behavior and `docs/acceptance.md` for manual
playtest checks. The earlier design remains in `docs/design_spec_v0.2_archive.md`.
Hiring, promotion, traits, save games and AI narration are not implemented in this
milestone. `Main` should only receive these changes after review and playtesting.
