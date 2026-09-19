extends Control

@onready var hud = $HUD
@onready var log_label: RichTextLabel = $MarginContainer/VBoxContainer/Log
@onready var choices_container: VBoxContainer = $MarginContainer/VBoxContainer/Choices
@onready var new_night_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/NewNightButton
@onready var next_hour_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/NextTickButton
@onready var next_update_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/NextUpdateButton
@onready var status_label: Label = $MarginContainer/VBoxContainer/Status
@onready var staff_container: HBoxContainer = $MarginContainer/VBoxContainer/Staff
@onready var tables_container: GridContainer = $MarginContainer/VBoxContainer/Tables

var assignment_visit: int = -1
var assignment_night: int = -1
var sim: Simulation
var phrasebook_pause_timer: Timer
var playback_delay: float = 0.35
var playback_active: bool = false
var pending_lines: Array = []
var table_selectors: Array[OptionButton] = []

func _ready() -> void:
	$MarginContainer/VBoxContainer/Goal.text = "Goal: %d completed visits · average departure satisfaction ≥ %.1f (includes bounced visits)" % [GameConfig.TARGET_COMPLETED_VISITS, GameConfig.TARGET_SATISFACTION]
	hud.wench_selector.wench_selected.connect(_on_wench_selected)
	sim = Simulation.new()
	sim.liquor_stock_changed.connect(hud.update_liquor)
	sim.gold_changed.connect(hud.update_gold)
	phrasebook_pause_timer = Timer.new()
	phrasebook_pause_timer.one_shot = true
	phrasebook_pause_timer.timeout.connect(_playback_step)
	add_child(phrasebook_pause_timer)
	new_night_button.pressed.connect(_start_new_night)
	next_hour_button.pressed.connect(_on_next_hour_button_pressed)
	next_update_button.pressed.connect(_on_next_update_button_pressed)
	_start_new_night()

func _start_new_night() -> void:
	phrasebook_pause_timer.stop()
	pending_lines.clear()
	playback_active = false
	_clear_choices()
	log_label.clear()
	_apply_result(sim.start_new_night())

func _on_next_hour_button_pressed() -> void:
	if playback_active or sim.phase != Simulation.Phase.BETWEEN_HOURS:
		return
	_apply_result(sim.advance_hour())

func _apply_result(result: Dictionary) -> void:
	phrasebook_pause_timer.stop()
	_clear_choices()
	pending_lines.clear()
	pending_lines.append_array(result.get("log_lines", []))
	for update in result.get("phrasebook_updates", []):
		pending_lines.append(update["text"])
	playback_active = true
	_refresh_dashboard()
	_playback_step()

func _playback_step() -> void:
	if not playback_active:
		return
	if not pending_lines.is_empty():
		_append_line(str(pending_lines.pop_front()))
		phrasebook_pause_timer.start(playback_delay)
		_update_controls()
		return
	if sim.phase == Simulation.Phase.ADMITTING:
		_apply_result(sim.process_next_client_entry())
		return
	if sim.phase == Simulation.Phase.PROCESSING:
		_apply_result(sim.process_next_table())
		return
	playback_active = false
	_show_choices(sim.pending_choices)
	_refresh_dashboard()

func _on_next_update_button_pressed() -> void:
	if not playback_active:
		return
	phrasebook_pause_timer.stop()
	_playback_step()

func _on_choice_button_pressed(choice_id: String) -> void:
	if playback_active or sim.phase != Simulation.Phase.AWAITING_CHOICE:
		return
	_apply_result(sim.apply_choice(choice_id))

func _show_choices(choices: Array) -> void:
	_clear_choices()
	for choice in choices:
		var button = Button.new()
		button.text = choice["text"]
		button.pressed.connect(_on_choice_button_pressed.bind(choice["id"]))
		choices_container.add_child(button)

func _clear_choices() -> void:
	_clear_container(choices_container)

func _clear_container(container: Node) -> void:
	for child in container.get_children():
		# Detach immediately so stale controls cannot be clicked this frame.
		container.remove_child(child)
		child.queue_free()

func _append_line(text: String) -> void:
	log_label.append_text(text + "\n")
	log_label.scroll_to_line(maxi(0, log_label.get_line_count() - 1))

func _update_controls() -> void:
	var can_manage = not playback_active and sim.phase == Simulation.Phase.BETWEEN_HOURS
	next_hour_button.disabled = not can_manage
	next_update_button.visible = playback_active
	var selecting = not playback_active and sim.has_pending_table_assignment()
	$MarginContainer/VBoxContainer/SelectionArea.visible = selecting
	hud.update_wench_selector(sim)
	hud.wench_selector.visible = selecting
	if selecting:
		assignment_visit = sim.pending_table_assignments[0]["visit_id"]
		assignment_night = sim.night_serial
	else:
		assignment_visit = -1
		assignment_night = -1
	for selector in table_selectors:
		selector.disabled = not can_manage or selector.get_meta("empty_slot", false)

func _refresh_dashboard() -> void:
	var phase_text = "Between hours — adjust assignments, then advance"
	if sim.phase == Simulation.Phase.CLOSED:
		phase_text = "Closed — start a new night to play again"
	elif sim.phase == Simulation.Phase.AWAITING_ASSIGNMENT:
		phase_text = "Assign staff to " + sim.get_next_pending_table_label()
	elif sim.phase == Simulation.Phase.ADMITTING:
		phase_text = "Guests arriving"
	elif sim.phase == Simulation.Phase.AWAITING_CHOICE:
		phase_text = "Decision pending"
	elif sim.phase == Simulation.Phase.PROCESSING:
		phase_text = "Service in progress"
	status_label.text = "%s | %d/%d hours complete | %s" % [sim._get_time_string(), sim.hour, GameConfig.HOURS_PER_NIGHT, phase_text]
	_clear_container(staff_container)
	for w in sim.wenches:
		var label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var state = w["current_state"]
		if state == "exhausted":
			state += " (%dh left)" % w["recovery_hours"]
		label.text = "%s · %s\nStamina %d/%d · %d tables · tips %d\nCharm %d · Service %d" % [w["name"], state, w["stamina"], w["max_stamina"], w["assigned_tables"].size(), w["tips_earned"], w["charm"], w["service"]]
		staff_container.add_child(label)
	_clear_container(tables_container)
	table_selectors.clear()
	hud.table_indicators.clear()
	for slot in range(1, GameConfig.NUM_TABLES + 1):
		var table: Dictionary = {}
		for candidate in sim.tables:
			if candidate["id"] == slot:
				table = candidate
				break
		var panel = VBoxContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label = Label.new()
		if table.is_empty():
			label.text = "Table %d · Empty\nWaiting for guests\n " % slot
		else:
			label.text = "Table %d · Visit %d · %d guests\nSatisfaction %d · Rowdiness %.1f\n%s" % [slot, table["visit_id"], table["group_size"], table["satisfaction"], table["rowdiness"], "UNSERVED" if table["is_unserved"] else table["active_wench"]]
		var row = HBoxContainer.new()
		var indicator = preload("res://TableIndicator.tscn").instantiate()
		row.add_child(indicator)
		row.add_child(label)
		panel.add_child(row)
		var selector = OptionButton.new()
		selector.set_meta("empty_slot", table.is_empty())
		selector.add_item("Empty" if table.is_empty() else "Assign staff…")
		selector.set_item_disabled(0, true)
		for w in sim.wenches:
			selector.add_item(w["name"])
			var index = selector.item_count - 1
			selector.set_item_metadata(index, w["name"])
			selector.set_item_disabled(index, w["current_state"] != "serving")
			if not table.is_empty() and table["active_wench"] == w["name"]:
				selector.select(index)
		if not table.is_empty():
			selector.item_selected.connect(_on_assignment_selected.bind(selector, table["visit_id"]))
		panel.add_child(selector)
		tables_container.add_child(panel)
		indicator.set_number(slot)
		hud.table_indicators.append(indicator)
		table_selectors.append(selector)
	hud.update_table_indicators(sim)
	_update_controls()

func _on_assignment_selected(index: int, selector: OptionButton, visit_id: int) -> void:
	if playback_active or sim.phase != Simulation.Phase.BETWEEN_HOURS:
		return
	var result = sim.reassign_table(visit_id, str(selector.get_item_metadata(index)))
	for line in result["log_lines"]:
		_append_line(line)
	_refresh_dashboard()

func _on_wench_selected(wench_name: String) -> void:
	if playback_active or not sim.has_pending_table_assignment():
		return
	_apply_result(sim.assign_wench_to_pending_table(wench_name, assignment_visit, assignment_night))
