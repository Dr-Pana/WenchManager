extends SceneTree

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	_test_guards_and_completion()
	_test_visit_identity_and_assignment()
	_test_choices()
	_test_arrival_assignments()
	_test_staff_recovery()
	_test_history_and_goal()
	_test_events_and_unserved()
	_test_seeded_nights()
	print("Simulation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fresh(seed_value: int = 12) -> Simulation:
	var sim = Simulation.new()
	sim.start_new_night(seed_value)
	return sim

func add_visit(sim: Simulation, slot: int, staff: String = "Brakka") -> Dictionary:
	var table = sim._make_table(slot, "Table %d" % slot, "poor", "human", 1)
	table["active_wench"] = staff
	table["is_unserved"] = staff == ""
	sim.tables.append(table)
	sim._sync_assignments()
	return table

func drain_hour(sim: Simulation) -> void:
	var budget = 100
	while sim.hour_in_progress and budget > 0:
		budget -= 1
		if sim.phase == Simulation.Phase.ADMITTING:
			sim.process_next_client_entry()
		elif sim.has_pending_table_assignment():
			var best = null
			for w in sim.wenches:
				if w["current_state"] == "serving" and (best == null or w["assigned_tables"].size() < best["assigned_tables"].size()):
					best = w
			sim.assign_wench_to_pending_table(best["name"], sim.pending_table_assignments[0]["visit_id"], sim.night_serial)
		elif sim.has_pending_choices():
			sim.apply_choice(sim.pending_choices.back()["id"])
		else:
			sim.process_next_table()
	check(budget > 0, "Hour must finish without a continuation loop")

func _test_guards_and_completion() -> void:
	var sim = fresh()
	sim.process_next_table()
	sim.apply_choice("invalid")
	check(sim.hour == 0, "Idle calls cannot advance time")
	check(sim._get_time_string() == "5pm", "Opening time")
	for i in range(GameConfig.HOURS_PER_NIGHT):
		sim.advance_hour()
		if sim.hour_in_progress:
			var index = sim.current_table_index
			sim.advance_hour()
			check(sim.current_table_index == index, "Cannot start a second hour during service")
		drain_hour(sim)
		check(sim.hour == i + 1, "Hour advances exactly once")
	check(sim.phase == Simulation.Phase.CLOSED, "Night closes")
	check(sim._get_time_string() == "1am", "Closing time")
	var summary = sim.get_night_summary()
	for i in range(4):
		sim.advance_hour()
		sim.process_next_table()
		sim.apply_choice("invalid")
		sim._calculate_night_summary()
	check(sim.hour == 8 and sim.get_night_summary() == summary, "Closed-night actions and summary reads are inert")

func _test_visit_identity_and_assignment() -> void:
	var sim = fresh()
	var first = add_visit(sim, 1)
	var middle = add_visit(sim, 2)
	var last = add_visit(sim, 3)
	sim._archive_visit(middle, "completed")
	check(sim._first_empty_slot() == 2, "First gap reused, not table count plus one")
	var replacement = add_visit(sim, sim._first_empty_slot())
	check(replacement["visit_id"] != middle["visit_id"], "Slot reuse creates a new visit")
	sim.reassign_table(replacement["visit_id"], "Mimi")
	check(replacement["active_wench"] == "Mimi" and last["active_wench"] == "Brakka", "Assignment targets one visit")
	check(sim.wenches[2]["assigned_tables"] == [2], "Assignment view uses slot IDs")
	check(not sim.wenches[1]["assigned_tables"].has(2), "Old staff assignment cleaned")
	sim.wenches[0]["current_state"] = "exhausted"
	sim.reassign_table(first["visit_id"], "Lysa")
	check(first["active_wench"] == "Brakka", "Exhausted staff cannot be assigned")
	sim.phase = Simulation.Phase.PROCESSING
	sim.reassign_table(first["visit_id"], "Mimi")
	check(first["active_wench"] == "Brakka", "Assignments locked during service")
	sim._archive_visit(replacement, "bounced")
	sim._archive_visit(replacement, "bounced")
	check(sim.visit_history.size() == 2 and sim.wenches[2]["assigned_tables"].is_empty(), "Removal is idempotent and clears staff assignment")

func _test_choices() -> void:
	var sim = fresh()
	var table = add_visit(sim, 1)
	table["rowdiness"] = 11.0
	table["hourly_consumption"] = 2
	sim.gold = 5
	var choice = sim._choice("free_round", "Comp", table)
	sim.phase = Simulation.Phase.AWAITING_CHOICE
	sim.pending_choices = [choice]
	var original_stock = sim.stock.duplicate()
	sim.apply_choice("stale")
	sim.process_next_table()
	check(sim.gold == 5 and sim.pending_choices.size() == 1, "Invalid choice and continuation preserve pending decision")
	sim.apply_choice(choice["id"])
	check(sim.gold == 5 and sim.stock["cheap_ale"] == original_stock["cheap_ale"] - 1, "Recovered action preserves sales and uses inventory once")
	sim.apply_choice(choice["id"])
	check(sim.gold == 5 and sim.stock["cheap_ale"] == original_stock["cheap_ale"] - 1 and sim.phase == Simulation.Phase.PROCESSING, "Duplicate choice cannot apply twice")
	var old_id = choice["id"]
	sim.start_new_night(12)
	table = add_visit(sim, 1)
	choice = sim._choice("free_round", "Comp", table)
	sim.phase = Simulation.Phase.AWAITING_CHOICE
	sim.pending_choices = [choice]
	sim.apply_choice(old_id)
	check(sim.has_pending_choices() and choice["id"] != old_id, "Old-night choice is invalid after restart")
	# A pending removal must not accidentally affect another occupied slot.
	var other = add_visit(sim, 2)
	sim.pending_choices = [sim._choice("bounce", "Clear", table)]
	sim.apply_choice(sim.pending_choices[0]["id"])
	check(sim.tables.size() == 1 and sim.tables[0]["visit_id"] == other["visit_id"], "Bounce targets only selected visit")

func _test_staff_recovery() -> void:
	var sim = fresh()
	var table = add_visit(sim, 1)
	add_visit(sim, 2)
	sim.hour_workloads = {"Brakka": 2}
	sim._update_staff_after_hour()
	check(sim.wenches[1]["stamina"] == 6, "Two-table workload drains two stamina once")
	sim.wenches[1]["stamina"] = 1
	sim._update_staff_after_hour()
	check(sim.wenches[1]["stamina"] == 0 and sim.wenches[1]["current_state"] == "exhausted", "Exhaustion clamps stamina and changes state")
	sim._refresh_coverage()
	check(table["active_wench"] != "Brakka", "Exhausted staff replaced")
	for i in range(GameConfig.EXHAUSTION_RECOVERY_HOURS - 1):
		sim._update_staff_after_hour()
		check(sim.wenches[1]["current_state"] == "exhausted", "Recovery waits full duration")
	sim._update_staff_after_hour()
	check(sim.wenches[1]["current_state"] == "serving" and sim.wenches[1]["stamina"] == 8, "Recovery restores availability and stamina")
	for w in sim.wenches:
		w["current_state"] = "exhausted"
	sim._refresh_coverage()
	check(table["is_unserved"] and table["active_wench"] == "", "No available staff marks table unserved")
	sim.wenches[0]["current_state"] = "serving"
	sim._refresh_coverage()
	check(not table["is_unserved"] and table["active_wench"] == "Lysa", "Previously unserved tables regain coverage")

func _test_history_and_goal() -> void:
	var sim = fresh()
	for slot in range(1, 4):
		var table = add_visit(sim, slot)
		table["satisfaction"] = 2
		table["peak_rowdiness"] = float(slot)
		sim._archive_visit(table, "completed")
	sim.phase = Simulation.Phase.CLOSED
	var before = sim.get_night_summary()
	check(before["goal_met"] and before["average_satisfaction"] == 2.0, "Departed visits count toward goal")
	check(before["peak_rowdiness"] == 3.0, "Rowdiest departed visit retained")
	sim._calculate_night_summary()
	sim._calculate_night_summary()
	check(sim.get_night_summary() == before, "Summary does not settle tips again")
	sim.start_new_night()
	sim.phase = Simulation.Phase.CLOSED
	check(not sim.get_night_summary()["goal_met"] and sim.get_night_summary()["visits"] == 0, "Empty night cannot meet objective")

func _test_events_and_unserved() -> void:
	var sim = fresh()
	var table = add_visit(sim, 1, "")
	var stock_before = sim.stock.duplicate()
	sim._apply_unserved_penalties_for_table(table)
	sim._update_table_rowdiness_for_table(table)
	check(table["satisfaction"] == -1 and sim.gold == 0 and sim.stock == stock_before, "Unserved table has no service transaction")
	check(is_equal_approx(table["event_chance"], table["rowdiness"] / 30.0 * 1.3), "Unserved event multiplier survives rowdiness update")
	check(sim._generate_phrasebook_update_for_table(table)["text"].contains("unserved"), "Unserved narration is safe with no staff")
	table["satisfaction"] = -30
	table["consumption"] = 5
	check(sim._calculate_table_tips(table) == 0, "Tips cannot become negative")
	sim.reassign_table(table["visit_id"], "Mimi")
	check(not sim._resolve_event(table, "request_refill").is_empty(), "Events explain outcome")
	check(not sim._resolve_event(table, "rowdy_noise").is_empty(), "Noise event explains outcome")

func _test_seeded_nights() -> void:
	var goals = 0
	for seed_value in range(30):
		var sim = fresh(seed_value)
		var replay = fresh(seed_value)
		# Empty templates must not affect simulation progress.
		sim.phrasebook_templates.clear()
		for i in range(8):
			sim.advance_hour()
			drain_hour(sim)
			replay.advance_hour()
			drain_hour(replay)
		check(sim.phase == Simulation.Phase.CLOSED and sim.tables.is_empty(), "Seed %d completes eight hours" % seed_value)
		check(sim.get_night_summary() == replay.get_night_summary(), "Seed %d deterministic replay independent of narration" % seed_value)
		check(sim.next_visit_id - 1 == sim.visit_history.size(), "Every admitted visit archived exactly once")
		for w in sim.wenches:
			check(w["stamina"] >= 0 and w["tips_earned"] >= 0, "Staff values remain nonnegative")
		if sim.get_night_summary()["goal_met"]:
			goals += 1
	print("Seeded baseline: %d/30 service goals met using automatic assignments and ignoring optional interventions" % goals)

func _test_arrival_assignments() -> void:
	var sim = fresh(1)
	sim.phase = Simulation.Phase.ADMITTING
	for i in range(20):
		sim.pending_client_queue.append({"social_status": "poor", "race": "human", "group_size": 1})
	sim.process_next_client_entry()
	check(sim.has_pending_table_assignment(), "Admitted group pauses for portrait assignment")
	var pending = sim.pending_table_assignments[0]
	var serial = sim.night_serial
	var visit_id = pending["visit_id"]
	var queue_size = sim.pending_client_queue.size()
	sim.process_next_client_entry()
	sim.process_next_table()
	sim.advance_hour()
	check(sim.pending_client_queue.size() == queue_size and sim.hour == 0, "Waiting assignment blocks all continuation paths")
	sim.assign_wench_to_pending_table("missing", visit_id, serial)
	sim.assign_wench_to_pending_table("Mimi", visit_id + 1, serial)
	check(sim.has_pending_table_assignment(), "Invalid staff and stale visit cannot consume assignment")
	sim.assign_wench_to_pending_table("Mimi", visit_id, serial)
	check(pending["active_wench"] == "Mimi" and sim.phase == Simulation.Phase.ADMITTING, "Assignment resumes admissions without processing time")
	sim.assign_wench_to_pending_table("Lysa", visit_id, serial)
	check(pending["active_wench"] == "Mimi", "Duplicate assignment is inert")
	drain_hour(sim)
	check(sim.hour == 1, "Multiple admissions finish exactly one hour")
	sim.start_new_night(1)
	sim.phase = Simulation.Phase.ADMITTING
	for i in range(20):
		sim.pending_client_queue.append({"social_status": "poor", "race": "human", "group_size": 1})
	sim.process_next_client_entry()
	sim.assign_wench_to_pending_table("Mimi", visit_id, serial)
	check(sim.has_pending_table_assignment(), "Previous-night assignment cannot target reused visit ID")
	# Every staff member unavailable must never create an impossible input prompt.
	sim.start_new_night(1)
	for w in sim.wenches:
		w["current_state"] = "exhausted"
		w["recovery_hours"] = 3
	sim.advance_hour()
	drain_hour(sim)
	check(sim.hour == 1 and not sim.has_pending_table_assignment(), "Unavailable roster does not deadlock admission")
