# Validation — One manageable night

Validated with Godot 4.5 stable (`876b29033`) on Linux x86_64.

- Clean editor import and scene startup: no script errors.
- Simulation suite: **720 checks, 0 failures**.
- Actual-scene UI suite: **37 checks, 0 failures**.
- Linux release export using matching 4.5 stable templates: successful.
- Both suites rerun against the exported executable using external test scripts:
  **720 + 37 checks, 0 failures**. The export loaded its packaged phrasebook.
- Tests cover 30 seeded nights and replay them with/without narration templates;
  game outcomes match. Each night completes exactly eight hours.
- `git diff --check`: clean.

The default-assignment baseline met the provisional service goal in 4 of 30 seeded
nights while ignoring optional interventions. This is a reproducible baseline,
not evidence of final game balance. Human playtesting should evaluate whether
reassignment and interventions provide sufficiently clear, useful choices.

UI verification used headless scene instantiation, control signals, timer playback
and layout bounds. A graphical desktop review was not available in this runtime;
visual appearance, window resizing and mouse/keyboard usability still need the
manual checks in `docs/acceptance.md`. No changes have been merged into Main.

To repeat export validation, build first, then pass each test script as an absolute
filesystem path to the exported executable's `--script` option. Test scripts are
excluded from the shipped pack but execute against its compiled game resources.
