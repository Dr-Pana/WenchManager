# Wench Manager – Design Spec v0.1

## 1. High-Level Concept

Fantasy tavern management sim focused on **barmaids ("wenches")** and their interactions with customers.

Tone: **spicy but light-hearted**. Comedy, innuendo, tavern chaos. No grimdark exploitation.

Target implementation:
- Start as **text-based** (Godot 4 + GDScript, simple UI with log + buttons).
- Later: optional graphical UI (portraits, tavern map, moving wench icons).

Core loop (per in-game day/night):
1. **Hiring Phase**: choose wenches to hire based on stats/traits.
2. **Prep Phase**: assign wenches to tables/zones, choose supplies and strategy.
3. **Action Phase**: semi-automated simulation where events unfold in ticks; player occasionally makes decisions in crises.

Current focus: **Action Phase**.

---

## 2. Action Phase – Current Implementation (v0.1)

Implemented in `scripts/simulation.gd` plus UI wiring in `scripts/main.gd`.

### 2.1 Tick Loop

- `start_new_night()`:
  - Resets tick counter.
  - Initializes wenches and tables with hardcoded example data.
  - Logs intro text.
  - Automatically calls `advance_tick()` once.

- `advance_tick()`:
  - `tick += 1`
  - Appends a `-- Tick N --` line to the log.
  - Calls `_update_stamina(logs)`.
  - For each table:
    - Rolls a random event via `_roll_event_for_table(table)`.
    - Resolves that event via `_resolve_event(table, event_id)` and logs the outcome.
  - After events, checks for crises:
    - If a table's `rowdiness >= 5`, it:
      - Logs a warning.
      - Adds a player choice: "Intervene personally at [table]".
      - Stores that choice in `pending_choices`.

- `apply_choice(choice_id)`:
  - Currently only handles `calm_[TableName]` choices.
  - Resets that table's `rowdiness` to 0.
  - Logs a calming intervention.
  - Clears `pending_choices`.

- `has_pending_choices()`:
  - Returns whether there are unresolved choices (used by UI to block tick advancement).

### 2.2 Random Event System (v0.1)

- `event_table` (global var): array of event descriptors with `id` and `weight`.

  Example:

  - `request_refill` (weight 6)
  - `flirt_minor` (weight 4)
  - `spill_drink` (weight 2)
  - `rowdy_noise` (weight 3)

- `_roll_event_for_table(table)`:
  - Does a weighted random pick from `event_table`.

- `_resolve_event(table, event_id)`:
  - Gets assigned wench via `_wench_for_table(table)`.
  - If no wench is found, logs "No wench assigned" and returns.
  - Handles events via `match`:
    - `request_refill`: customer wants refills; wench responds.
    - `flirt_minor`: customer flirts lightly with the wench.
    - `spill_drink`: wench spills a drink.
    - `rowdy_noise`: table shouts; `rowdiness += 1`.

  - For some events, calls `_event_check(w, table, difficulty, success_msg, fail_msg)`.

- `_event_check(...)`:
  - Computes a roll:

    `roll = w["charm"] + randi() % 5 - fatigue_penalty`

    where:

    `fatigue_penalty = int((w["max_stamina"] - w["stamina"]) / 2)`

  - If `roll >= difficulty`:
    - Logs success message.
    - `table["satisfaction"] += 2`
  - Else:
    - Logs failure message (orange warning).
    - `table["satisfaction"] -= 2`
    - `table["rowdiness"] += 1`

### 2.3 Data Model – Current State

#### Wench (Dictionary)

Fields:
- `name: String`
- `charm: int`
- `service: int`
- `stamina: int`
- `max_stamina: int`
- `assigned_table: String` (e.g. "Table 1")
- `traits: Array[String]` (currently unused in logic)

Initialized via `_make_wench(name, charm, service, stamina, table_label)`.

#### Table (Dictionary)

Fields:
- `label: String` (e.g. "Table 1")
- `group: String` (e.g. "Dwarven miners", "Noble couple")
- `satisfaction: int` (starts at 0)
- `patience: int` (currently unused, default 5)
- `rowdiness: int` (starts at 0)

---

## 3. Design Rules / Intentions

- **Action Phase is the heart**: it should feel like a living tavern with emergent stories.
- Wenches are **main characters**, not faceless stats:
  - We want traits and personalities to matter in events.
- Customers come in archetypes (dwarves, nobles, mercenaries, etc.) that:
  - Prefer different behaviors.
  - Generate different event types.
- Player choice:
  - Appears at **key crisis points**, not constantly.
  - Choices should have clear trade-offs (safety vs profit, decorum vs chaos, etc.).
- Game should be expandable:
  - Later we plug in Hiring Phase and Prep Phase that feed into Action Phase.

---

## 4. Backlog / Next Features

- Make events depend on customer group:
  - Dwarves → more `rowdy_noise`, `spill_drink`.
  - Nobles → more `flirt_minor`, "offended" events.
  - Mercenaries → mixture of rowdy and playful.
- Implement basic **traits** that modify `_event_check`:
  - `Flirtatious` → bonus on flirt events.
  - `Clumsy` → higher chance of `spill_drink`, but maybe funny recoveries.
- Use `service` and `stamina` stats, not only `charm`.
- Add simple end-of-night summary:
  - Average satisfaction
  - Gold earned
  - Which wench is most tired
- Add `supplies` (ale, wine, food) and connect them to events.

