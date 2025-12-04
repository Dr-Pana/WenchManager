# Wench Manager – Design Spec v0.2

## 1. High-Level Concept

Fantasy tavern management sim focused on **barmaids ("wenches")** and their interactions with customers.

Tone: **spicy but light-hearted**. Comedy, innuendo, tavern chaos. No grimdark exploitation.

Target implementation:
- Start as **text-based** (Godot 4 + GDScript, simple UI with log + buttons).
- Later: optional graphical UI (portraits, tavern map, moving wench icons).

Core loop (per in-game day/night):
1. **Hiring Phase**: choose wenches to hire based on stats/traits.
2. **Prep Phase**: assign wenches to tables/zones, choose supplies and strategy.
3. **Action Phase**: semi-automated simulation where events unfold in hours; player occasionally makes decisions in crises.

Current focus: **Action Phase**.

---

## 2. Action Phase – Current Implementation (v0.2)

Implemented in `scripts/simulation.gd` plus UI wiring in `scripts/main.gd`.

**Key State Variables:**
- `current_hour_tables: Array` - Randomized table order for current hour
- `current_table_index: int` - Which table is currently being processed (-1 when not processing)
- `hour_in_progress: bool` - Whether we're mid-hour processing
- `pending_choices: Array` - Choices awaiting player decision
- `phrasebook_templates: Array[String]` - Loaded phrasebook templates from `phrasebook.md`

### 2.1 Table-by-Table Processing System

The hour loop has been refactored to process tables **one at a time** in random order, with user interaction between each table. This enables per-table decision-making and fixes issues where multiple choices appeared simultaneously.

**State Tracking:**
- `current_hour_tables: Array` - Randomized table order for current hour
- `current_table_index: int` - Which table is currently being processed
- `hour_in_progress: bool` - Whether we're mid-hour processing

**Processing Flow:**
- Hour increments **only after all tables have been processed** (not at the start)
- Tables are processed in **random order** each hour
- Each table update includes: stamina/availability checks, rowdiness/consumption updates, events, phrasebook updates, and choices
- After processing a table, the system waits for user interaction (choices or acknowledgment) before moving to the next table

### 2.2 Hour Loop

- `start_new_night()`:
  - Resets hour counter (starts at hour 0, service begins at 5pm).
  - Resets table-by-table processing state.
  - Initializes 3 wenches (Lysa, Brakka, Mimi) and 6 tables with random data.
  - Assigns 2 tables to each wench with round-robin backup assignments.
  - Loads phrasebook templates from `phrasebook.md`.
  - Logs intro text with stock report and table overview.

- `advance_hour()`:
  - **First call**: Randomizes table order, initializes state, processes first table
  - **Subsequent calls**: Should not happen (hour in progress)
  - Appends a `-- Hour N (time) --` line to the log (e.g., "Hour 1 (5pm)", "Hour 10 (3am)").
  - Hour increments **only after all tables are processed** (in `process_next_table()` when no more tables remain).

- `process_next_table()`:
  - Processes a **single table**:
    - Updates stamina/availability/unserved penalties for that table's wench
    - Updates rowdiness and consumption for that table
    - Generates phrasebook update for that table
    - Rolls and resolves events for that table
    - Checks for rowdiness alerts and fistfights
  - Returns result dictionary with logs, choices, and phrasebook updates for that one table
  - Automatically advances to next table index
  - If last table, increments hour and clears state

- `apply_choice(choice_id)`:
  - Handles multiple choice types:
    - `fistfight_acknowledge_[TableName]`: Bounces the table, removes it, calculates lost tips
    - `intervene_free_round_[TableName]`: Offers free round (satisfaction +2, rowdiness -3, consumes stock)
    - `intervene_bouncer_[TableName]`: Steps in personally (satisfaction -1, rowdiness -2)
    - `intervene_ignore_[TableName]`: Ignores the situation (no effect)
  - After applying choice, **automatically continues to next table** if hour is in progress
  - Returns Dictionary with next table's results (enables auto-continue flow)

- `has_pending_choices()`:
  - Returns whether there are unresolved choices (used by UI to block hour advancement).

### 2.3 Phrasebook System

The phrasebook system provides dynamic narrative updates for each table, showing what's happening throughout the night.

**Phrasebook Templates:**
- Loaded from `phrasebook.md` file at start of night
- Templates contain placeholders: `{table}`, `{amount}`, `{liquor}`, `{wench}`, `{state}`
- One phrasebook update is generated per table per hour
- Updates are displayed with a **1-second pause** between each update

**Wench Mood States:**
- Determined by stamina percentage and active table count:
  - `exhausted` (0% stamina)
  - `weary` (≤20% stamina)
  - `tired` (≤40% stamina, 1 table) / `stressed` (≤40% stamina, multiple tables)
  - `cheerful` (≤60% stamina, 1 table) / `focused` (≤60% stamina, multiple tables)
  - `energetic` (≤80% stamina, 1 table) / `cheerful` (≤80% stamina, multiple tables)
  - `energetic` (>80% stamina)

**Display Flow:**
- Phrasebook updates are displayed sequentially with 1-second pauses
- After all updates are displayed, choices are shown (if any)
- If no choices, system auto-continues to next table after a brief pause

### 2.4 Rowdiness Alerts and Interventions

**Rowdiness Alert Levels:**
- **Dangerous (10-14)**: Table is getting dangerously rowdy
  - Player choices:
    - "Free round on the house" - Costs stock, satisfaction +2, rowdiness -3
    - "Bouncer call (step in personally)" - Satisfaction -1, rowdiness -2
    - "Ignore" - No effect
- **Fistfight (15+)**: A fistfight breaks out
  - Player choice: "Acknowledge (Table bounced)" - Table is removed, lost tips calculated

**Intervention Effects:**
- **Free Round**: Customers cheer, satisfaction increases, rowdiness subsides. Consumes one hour's worth of liquor from stock (no gold cost).
- **Bouncer Call**: Customers quiet down but aren't happy about being scolded. Reduces rowdiness but decreases satisfaction.
- **Ignore**: No immediate effect, but rowdiness continues to increase.

### 2.5 Random Event System (v0.1)

- `event_table` (global var): array of event descriptors with `id` and `weight`.

  Example:

  - `request_refill` (weight 6)
  - `flirt_minor` (weight 4)
  - `spill_drink` (weight 2)
  - `rowdy_noise` (weight 3)

- `_roll_event_for_table(table)`:
  - First checks if an event should occur based on `table["event_chance"]` (derived from rowdiness).
  - If event occurs, does a weighted random pick from `event_table`.
  - Returns empty string if no event occurs this hour.

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

    `roll = w["charm"] + randi() % 5 - fatigue_penalty + race_modifier`

    where:

    `fatigue_penalty = int((w["max_stamina"] - w["stamina"]) / 2)`
    
    `race_modifier = race_compatibility[wench_race][client_race]`

  - If `roll >= difficulty`:
    - Logs success message.
    - `table["satisfaction"] += 2`
  - Else:
    - Logs failure message (orange warning).
    - `table["satisfaction"] -= 2`
    - `table["rowdiness"] += 1`
    - Updates `event_chance` based on new rowdiness.

### 2.6 Data Model – Current State

#### Wench (Dictionary)

Fields:
- `name: String`
- `charm: int`
- `service: int`
- `stamina: int`
- `max_stamina: int`
- `assigned_tables: Array[String]` (e.g. ["Table 1", "Table 2"])
- `current_state: String` — `"serving" | "socializing" | "exhausted" | "injured"` (default: "serving")
- `race: String` (e.g. "human", "elf", "dwarf", "orc", "tiefling")
- `traits: Array[String]` (currently unused in logic)

Initialized via `_make_wench(name, charm, service, stamina, assigned_tables, race)`.

**Multi-Wench Coverage:**
- Each wench can be assigned multiple tables (currently 2 tables per wench with 6 tables total).
- When a wench becomes unavailable, backup wenches are automatically promoted.

#### Table (Dictionary)

Fields:
- `id: int` (unique table identifier)
- `label: String` (e.g. "Table 1")
- `group: String` (legacy field, kept for backward compatibility)
- `description: String` (auto-generated, e.g. "A small group of rowdy noble dwarves")
- `social_status: String` (e.g. "poor", "merchant", "noble", "adventurer", "priestly")
- `race: String` (e.g. "human", "dwarf", "elf", "orc", "tiefling")
- `group_size: int` (1-6, number of customers)
- `rowdiness: float` (0.0-10.0, starts at 0, increases per hour)
- `consumption: int` (tracks how much liquor consumed in pints, affects drunkenness)
- `liquor_preference: String` (derived from social_status: "cheap ale", "cheap wine", "mead", "strong ale", "good wine")
- `event_chance: float` (0.0-1.0, calculated as `rowdiness / 30.0`)
- `resource_drain_rate: float` (calculated from social_status base rate × group_size modifier)
- `attitude_modifiers: Dictionary` (race compatibility info, for future use)
- `satisfaction: int` (starts at 0)
- `patience: int` (currently unused, default 5)
- `active_wench: String` (name of currently serving wench)
- `backup_wenches: Array[String]` (names of backup wenches that can cover this table)
- `is_unserved: bool` (true if no wench is currently serving this table)

**Table Generation:**
- Tables are randomly generated each night via `_init_tables()` (currently 6 tables).
- Social status: weighted random (poor/merchant/adventurer more common, noble/priestly rarer).
- Race: equal chance among available races.
- Group size: weighted toward smaller groups (1-6 people).
- Wench assignments are set up via `_assign_wenches_to_tables()` with round-robin backup assignments.

**Rowdiness System:**
- Rowdiness starts at 0 and increases each hour based on:
  1. **Race modifier**: Orcs (0.4/hour) > Dwarves (0.3) > Tieflings (0.2) > Humans (0.15) > Elves (0.1)
  2. **Group size**: 0.3 per person per hour (e.g., 3 people = 0.9/hour)
  3. **Drunkenness**: `consumption * 0.2`, where consumption is in pints (integer)
- Formula: `rowdiness_increase = race_modifier + (group_size * 0.3) + (consumption * 0.2)`
- Rowdiness can exceed 10 (no upper limit) - values 15+ trigger fistfights
- Event chance is recalculated whenever rowdiness changes: `event_chance = rowdiness / 30.0`
- Table description updates dynamically to reflect current rowdiness level (calm → moderate → rowdy → very rowdy)
- **Alert thresholds**:
  - 10-14: Dangerous rowdiness (intervention choices available)
  - 15+: Fistfight (table must be bounced)

**Social Status to Liquor Mapping:**
- Poor → cheap ale
- Merchant → cheap wine
- Noble → mead
- Adventurer → strong ale
- Priestly → good wine

**Resource Consumption (Liquor):**
- Liquor is tracked in **pints** (integers only - no fractions).
- Consumption per hour: `ceil(group_size * base_drain_rate)` pints
  - Base rate by social status: Poor (0.8), Merchant (1.0), Noble (1.5), Adventurer (1.3), Priestly (0.9)
  - Minimum 1 pint per hour per table (even for single person)
- Starting stock (balanced for 10-hour shift): Cheap ale (25), Cheap wine (20), Strong ale (18), Mead (15), Good wine (12)
- When a liquor type runs out: table satisfaction drops, rowdiness increases, customers become unhappy

**Liquor to Price Mapping (per pint):**
- Cheap ale: 1 gold/pint
- Cheap wine: 3 gold/pint
- Strong ale: 5 gold/pint
- Mead: 7 gold/pint
- Good wine: 10 gold/pint

**Race Compatibility:**
- Race compatibility modifiers affect event checks:
  - Human + Dwarf: +1
  - Elf + Elf: +2
  - Elf + Orc: -2
  - Tiefling + Human: -1
  - (See `race_compatibility` table in code for full matrix)

### 2.4 End-of-Night Summary

- Automatically triggers after 10 hours in `advance_hour()` (service runs 5pm-3am).
- Displays a summary in the log with:
  - **Average satisfaction**: Average of all tables' satisfaction values (formatted to 1 decimal place).
  - **Total gold earned**: Sum of per-table earnings, calculated separately for each table.
  - **Most tired wench**: Wench with the lowest current stamina value (name and stamina displayed).
  - **Rowdiest table**: Table with the highest rowdiness value (label and rowdiness displayed, formatted to 1 decimal place).

**Gold Calculation:**
- Each table's earnings calculated separately using the formula:
  - `table_earnings = consumption * liquor_price * 2 * (1 + satisfaction/10)`
- Where:
  - `consumption`: Total liquor consumed by the table in pints (accumulated over hours, integer).
  - `liquor_price`: Base price per pint from `liquor_prices` dictionary based on table's `liquor_preference`.
  - `satisfaction`: Table's current satisfaction value.
- Total gold is the sum of all table earnings (rounded to whole number for display).

**Implementation:**
- `_calculate_night_summary()`: Computes all summary statistics and returns formatted log lines.
- Called automatically from `advance_hour()` when `hour >= 10`.

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

- Make events depend on customer race/social status:
  - Dwarves → more `rowdy_noise`, `spill_drink`.
  - Nobles → more `flirt_minor`, "offended" events.
  - Orcs → more rowdy events overall.
- Implement basic **traits** that modify `_event_check`:
  - `Flirtatious` → bonus on flirt events.
  - `Clumsy` → higher chance of `spill_drink`, but maybe funny recoveries.
- Use `service` and `stamina` stats, not only `charm`.
- Add `supplies` (ale, wine, food) and connect them to events:
  - Track actual resource consumption (implemented: uses integer pints)
  - Events fail if supplies run out
  - Different social statuses consume different amounts
- Implement resource management:
  - Track available supplies per liquor type (implemented: integer pints)
  - Consumption reduces supplies based on group size, social status, and `liquor_preference`
  - Out of supplies = unhappy customers, increased rowdiness (implemented)
- Implement **Promotion/Table Filling System**:
  - **Prep Phase**: Before opening, assign maids to "promotion" (luring passersby into the tavern).
- **Table Filling**: Each hour, maids assigned to promotion attempt to lure groups into the tavern.
  - All outside maids combine their charm for a single roll per hour to attract customers.
  - Success rate based on combined charm of all maids on promotion duty.
  - On success, a new group arrives and occupies an empty table.
- **Player-Controlled Reassignment**: Between hours, the Manager (player) can reassign maids between promotion and table service.
    - Each occupied table requires a maid to serve it.
    - Player must balance: more maids on promotion = more customers arrive, but fewer maids serving = potential service issues.
    - Strategic decision: when to pull maids from promotion to serve tables, and when to send them back outside to attract more customers.
  - **Charm Importance**: Charm stat plays a crucial role in success rate for attracting customers.

---

## 5. AI-Assisted Narrative Layer (Planned)

### 5.1 Vision

Wench Manager is designed to support an optional **AI-driven narrative layer** that sits on top of a deterministic core simulation.

Goal: 
- The **simulation** handles rules, stats, outcomes, and balance.
- The **AI layer** turns those outcomes into rich, varied text: unique wench personalities, table banter, nightly events, etc.
- Players should *ideally* never have to read the exact same text twice for major beats.

LLM integration (e.g. via OpenAI API) is planned for:
- **Character generation** (personality, backstory, race, mannerisms) from a small set of traits and stats.
- **Event flavor text** (what happens at each table) based on the current state of the tavern.
- **Summaries/epilogues** (e.g., “How did tonight go?” in narrative form).

### 5.2 Core Design Principle

**Deterministic Core, Generative Skin.**

- The game logic (in `simulation.gd` etc.) must:
  - Decide *what actually happens*: success/failure, stamina, satisfaction changes, rowdiness, etc.
  - Work entirely without AI: no API calls required, fully playable in “offline / no-LLM” mode.
- The AI layer:
  - Takes structured **state snapshots** (e.g. “Brakka won an arm-wrestling match vs dwarves at Table 1 with high rowdiness”) and turns them into **flavor text** and **character details**.
  - Never becomes the single source of truth for game state.

### 5.3 Integration Points (Planned)

1. **Character Generation**
   - Input:
     - Core stats: charm, service, stamina, etc.
     - A small set of rolled traits (e.g. `["Flirtatious", "Clumsy"]`).
     - A few structural constraints (e.g. max 1–2 “negative” quirks).
   - Output (from AI):
     - Personality blurb (1–3 paragraphs).
     - Background hooks (e.g. “Grew up in a mining town”, “Owes money to a loan shark”).
     - Race / appearance description.
   - Storage:
     - Stored as text fields on the wench object and/or in a separate JSON/resource file keyed by `wench_id`.

2. **Nightly Event Deck**
   - Each night, the sim constructs a **structured list of potential events** based on:
     - Which wenches are on shift.
     - Which customer groups are present.
     - Current tavern mood, supplies, and strategy.
   - Input to AI:
     - A compact summary of the night setup.
     - A few examples of event *types* the sim understands (e.g. “flirt_minor”, “spill_drink”, “rowdy_noise”).
   - Output (from AI):
     - A set of flavored event descriptions + optional custom tags/labels that still map to known mechanics.
   - Constraint:
     - The *mechanical effect* of each event (which stats roll, what gets modified) remains defined in code.
     - The AI can vary text and minor details, but not the rules.

3. **Moment-to-Moment Narration (Optional)**
   - For important rolls / crises, the sim can call the AI with:
     - The raw outcome (success/failure, involved wench, table, archetypes, traits).
   - Output:
     - One or two sentences of unique tavern narration instead of a fixed string.
   - This is optional and should be easily toggleable (e.g. a “Narrative AI: On/Off” setting).

4. **End-of-Night Summaries**
   - Input:
     - Aggregate stats: average satisfaction, rowdiness incidents, biggest tip, most exhausted wench, etc.
   - Output:
     - A short “tavern chronicle” summarizing the night’s highlights in prose form.

### 5.4 Architectural Requirements

- The sim must expose **clean, compact state snapshots** that can be serialized and fed to an LLM:
  - Example: `NightState`, `WenchSnapshot`, `TableSnapshot`, `EventOutcome`.
- Text output should be **separated from core logic**:
  - No hard-coded text glued to game rules where it’s hard to swap out.
  - Instead, the sim emits **event codes + parameters** (e.g. `("flirt_minor", wench_id, table_id, success)`), and a narrative layer turns this into text.
- There will be a single, replaceable **Narration Adapter** (not yet implemented) responsible for:
  - Mapping events and entities to text in one of two modes:
    - Purely scripted (no AI, uses localized strings/templates).
    - AI-driven (LLM calls, possibly caching generated text).

### 5.5 Data Model Groundwork (Current & Planned)

Current plan for incremental changes:

1. **Wench data structure**
   - Add (planned fields):
     - `id: String` (stable identifier, not just display name).
     - `personality_text: String` (initially empty; can be filled by AI later).
     - `backstory_text: String` (same as above).
   - These are *purely narrative*; core sim ignores them.

2. **Event logging**
   - Internally, events should be represented as:
     - `event_id: String` (e.g. `"flirt_minor"`, `"spill_drink"`, `"rowdy_noise"`)
     - `actor_wench_id: String`
     - `table_label: String`
     - `outcome: String` (e.g. `"success"`, `"failure"`)
   - The current direct string logging is acceptable for v0.1, but in later versions:
     - There should be a layer that maps these event records into either:
       - Fixed string templates; or
       - LLM-generated narration.

3. **LLM Integration Constraints**
   - All LLM calls:
     - Must be **non-blocking** from a design perspective (game can be paused / loading icon shown if needed).
     - Must be optional; if the API is unreachable, the game falls back to template-based text.
   - Any AI-generated content should be:
     - Cached and keyed by `wench_id`, `night_id`, and/or `event_id` to avoid unnecessary repeat calls.


---

# 6. New Mechanics – Failure, Success, and Workload Systems (v0.2 Additions)

These additions expand the Action Phase with meaningful victory/failure conditions and multi-wench load sharing.  
They do **not** replace existing mechanics; they build on top of them.  


## 6.1 Table Meltdown (Failure Condition)

**Trigger**
- A table’s `rowdiness >= 8` **and** a failed event drops `satisfaction <= -5`.

**Effects**
- The table refuses to pay; its earnings become **0** for the night.
- Assigned wench suffers a stamina penalty (**−3 to −6**).
- Table becomes **closed** for the rest of the night.
- If a prior intervention choice was available but ignored, additional negative flavor text may appear (future AI layer integration).

---

## 6.2 Wench Exhaustion (Burnout)

**Trigger**
- Wench `stamina <= 0`.

**Effects**
- Wench enters `current_state = "exhausted"` for **3 hours**.
- All her tables temporarily become **unserved**.
- Unserved tables accumulate:
  - `rowdiness += 1` per hour  
  - `satisfaction -= 1` per hour  
  - `event_chance *= 1.3`  
- Player must reassign another wench or risk a **meltdown cascade**.

---

## 6.3 Success Bonus – “Invited to Drink”

**Trigger**
- Table `satisfaction >= 10`, **or**
- Wench with `charm >= 8` succeeds an event.

**Effects**
- Customers invite the wench to drink with them.
- Auto-charge: **5×** the liquor price (big gold spike).
- Wench becomes unavailable:
  - `current_state = "socializing"` for **2 hours**.
- All other tables she was covering become **unserved** unless reassigned.
- The inviting table gains `satisfaction += 3`.

---

## 6.4 Multi-Wench Coverage Model (Load Sharing) [IMPLEMENTED]

Replaces strict 1:1 wench-to-table assignment with a flexible system. Currently configured with 6 tables and 3 wenches (2 tables per wench).

### New Wench Fields
- `assigned_tables: Array[String]`
- `current_state: String` — `"serving" | "socializing" | "exhausted" | "injured"`

### New Table Fields
- `active_wench: String`
- `backup_wenches: Array[String]`
- `is_unserved: bool`

### Coverage Rules
- Every table must have at least **one active wench**.
- If an assigned wench becomes unavailable:
  - System automatically promotes a backup wench from `backup_wenches`.
  - If none are available → table becomes **unserved** and suffers penalties (see above).

### Penalties for Overworking
To prevent a single wench from covering the entire tavern:
- +1 stamina drain **per extra table** beyond her first.
- +1 or +2 difficulty added to event checks.
- −10% service efficiency per extra table.

---

## 6.5 Development Notes (For Implementation Later)

- These systems will require expanding `simulation.gd` event resolution.
- Prep Phase will be updated to allow multi-table assignment UI.
- The AI narrative layer can later provide unique text for meltdowns, exhaustion, and drinking scenes.

##6.6 Personal notes
- ~~To-do: If a liquor runs out, table's satisfaction drops and rowdiness increases fast.~~ (Implemented: satisfaction drops by 2-3, rowdiness increases by 1-2 when out of stock)
- Future: The maid can roll to persuade them to switch liquor when preferred type runs out.