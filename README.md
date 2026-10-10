# Wench Manager

A Godot 4.5 tavern-management prototype with a playable **Behind the bar** counter loop:
assign staff on a graphical floor, prepare orders, count change, and settle each sale.
Eight hourly intervals, six table slots and the original three staff portraits remain.

## Run

Import `project.godot` in **Godot 4.5 stable** and press **F5**.
The default scene is `CounterMain.tscn`; the older dashboard remains in `Main.tscn` (F6).
No plugins, API keys or external dependencies are required.

Open the doors, assign arriving groups with staff portraits, then fill each order
using the bottle controls. Count out change with coin buttons and **Serve & settle**.
Time pauses for player input. Items can be returned from the tray before settlement.
Between hours click a table and select a portrait to reassign its server.

Idle staff recover 2 stamina per hour; exhausted staff recover fully after one hour.
Closing results appear at 1am. **New Night** asks before clearing an active run.

See [the counter play guide](docs/counter-service.md) for shortcuts, transaction rules,
validation and next design decisions. The reference viewport is 1440 × 960 and scales
with the window. This first counter build uses one abstract currency and unlimited
change denominations; finite cash, campaign saves and faction systems are future work.

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

See `docs/dashboard.md` for the live UI and its validation.
See `docs/reconciliation.md` for what was preserved and combined.
See `design_spec.md` for the current behavior and `docs/acceptance.md` for manual
playtest checks. The earlier design remains in `docs/recovered_design_archive.md`.
Hiring, promotion, traits, save games and AI narration are not implemented in this
milestone. `Main` should only receive these changes after review and playtesting.
