extends SceneTree

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func flush_playback(ui) -> void:
	var budget = 300
	while ui.playback_active and budget > 0:
		budget -= 1
		ui._on_next_update_button_pressed()
	check(budget > 0, "UI playback must reach a decision or idle boundary")

func run() -> void:
	var ui = load("res://Main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	check(ui.phrasebook_pause_timer.timeout.get_connections().size() == 1, "Exactly one timer callback")
	# Restart while initial text is still playing.
	ui._start_new_night()
	flush_playback(ui)
	check(ui.sim.hour == 0 and not ui.next_hour_button.disabled, "Restart resets playback and unlocks opening")
	check(ui.table_selectors.size() == 6 and ui.staff_container.get_child_count() == 3, "Dashboard has six slots and three staff")
	for selector in ui.table_selectors:
		check(selector.disabled, "Empty-slot assignment is disabled")
	# Test timer-driven playback independently from skip-button playback.
	ui.playback_delay = 0.001
	ui._start_new_night()
	var timer_frames = 120
	while ui.playback_active and timer_frames > 0:
		timer_frames -= 1
		await process_frame
	check(not ui.playback_active and ui.sim.hour == 0, "Timer playback completes without advancing an idle night")
	ui.playback_delay = 0.35
	# Real selector signal changes the simulation and both dashboard views.
	var table = ui.sim._make_table(1, "Table 1", "poor", "human", 1)
	table["active_wench"] = "Brakka"
	ui.sim.tables.append(table)
	ui.sim._sync_assignments()
	ui._refresh_dashboard()
	var selector = ui.table_selectors[0]
	selector.item_selected.emit(3)
	check(table["active_wench"] == "Mimi", "Selector signal reassigns the correct visit")
	check(ui.sim.wenches[2]["assigned_tables"] == [1], "Dashboard and staff assignments agree")
	# Reproduce the recovered Table 2 indicator/assignment report.
	var second = ui.sim._make_table(2, "Table 2", "poor", "human", 1)
	second["is_unserved"] = true
	ui.sim.tables.append(second)
	ui.sim.pending_table_assignments = [second]
	ui.sim.phase = Simulation.Phase.AWAITING_ASSIGNMENT
	ui._apply_result(ui.sim._result())
	flush_playback(ui)
	await process_frame
	check(ui.hud.wench_selector.visible, "Portraits appear for pending arrival")
	check(ui.hud.table_indicators[1].wench_label.text == "!", "Pending Table 2 visibly unserved")
	check(ui.next_hour_button.get_global_rect().end.y <= root.get_visible_rect().size.y, "Portrait assignment fits viewport")
	ui.hud.wench_selector.mimi_button.pressed.emit()
	check(second["active_wench"] == "Mimi" and ui.hud.table_indicators[1].wench_label.text == "Mim", "Table 2 indicator updates immediately after portrait selection")
	flush_playback(ui)
	check(ui.sim.hour == 1 and not ui.playback_active, "Assignment resumes and finishes service without freezing")
	# Restart during a pending portrait assignment.
	ui.sim.pending_table_assignments = [table]
	ui.sim.phase = Simulation.Phase.AWAITING_ASSIGNMENT
	ui._apply_result(ui.sim._result())
	flush_playback(ui)
	ui._start_new_night()
	flush_playback(ui)
	check(not ui.hud.wench_selector.visible and ui.sim.pending_client_queue.is_empty(), "Restart clears pending portraits and client queue")
	table = ui.sim._make_table(1, "Table 1", "poor", "human", 1)
	table["active_wench"] = "Brakka"
	ui.sim.tables.append(table)
	# Force a real crisis through table processing, then restart at the choice.
	table["rowdiness"] = 16.0
	ui.sim.phase = Simulation.Phase.PROCESSING
	ui.sim.current_hour_tables = [table]
	ui.sim.current_table_index = 0
	ui._apply_result(ui.sim.process_next_table())
	check(ui.next_hour_button.disabled, "Advance locked during narration")
	flush_playback(ui)
	check(ui.choices_container.get_child_count() == 1, "Crisis displays one actionable button")
	var stale_id = ui.sim.pending_choices[0]["id"]
	# Bounds check includes maximum choice stack at the supported viewport.
	ui._show_choices([{"id": "a", "text": "One"}, {"id": "b", "text": "Two"}, {"id": "c", "text": "Three"}])
	await process_frame
	await process_frame
	check(ui.next_hour_button.get_global_rect().end.y <= root.get_visible_rect().size.y, "Controls fit the viewport with three choices")
	check(ui.log_label.size.y >= 130.0, "Log retains useful space")
	ui._start_new_night()
	flush_playback(ui)
	ui._on_choice_button_pressed(stale_id)
	ui._playback_step()
	check(ui.sim.hour == 0 and ui.sim.pending_choices.is_empty(), "Old choice and stale playback cannot alter restart")
	# Empty phrasebook must never strand an active hour in the UI.
	ui._apply_result(ui.sim.start_new_night(12))
	flush_playback(ui)
	ui.sim.phrasebook_templates.clear()
	var iterations = 0
	while ui.sim.phase != Simulation.Phase.CLOSED and iterations < 200:
		iterations += 1
		flush_playback(ui)
		if ui.sim.phase == Simulation.Phase.BETWEEN_HOURS:
			ui.next_hour_button.pressed.emit()
		elif ui.sim.has_pending_table_assignment():
			for button in [ui.hud.wench_selector.lysa_button, ui.hud.wench_selector.brakka_button, ui.hud.wench_selector.mimi_button]:
				if not button.disabled:
					button.pressed.emit()
					break
		elif ui.sim.phase == Simulation.Phase.AWAITING_CHOICE:
			ui.choices_container.get_child(ui.choices_container.get_child_count() - 1).pressed.emit()
	flush_playback(ui)
	check(ui.sim.hour == 8 and ui.sim.phase == Simulation.Phase.CLOSED, "UI completes eight hours without phrasebook")
	check(ui.next_hour_button.disabled and ui.choices_container.get_child_count() == 0, "Closed night has no advance or choice controls")
	check(ui.log_label.get_parsed_text().contains("End of Night Summary"), "UI displays results")
	ui.new_night_button.pressed.emit()
	flush_playback(ui)
	check(ui.sim.hour == 0 and ui.sim.visit_history.is_empty(), "New Night after closing clears history")
	check(ui.phrasebook_pause_timer.timeout.get_connections().size() == 1, "Restarts never accumulate timer callbacks")
	ui.queue_free()
	await process_frame
	print("UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
