extends Control

@onready var hud = $HUD
@onready var log_label: RichTextLabel = $MarginContainer/VBoxContainer/Log
@onready var choices_container: VBoxContainer = $MarginContainer/VBoxContainer/Choices
@onready var new_night_button: Button = $Footer/NewNightButton
@onready var next_hour_button: Button = $Footer/NextTickButton
@onready var next_update_button: Button = $Footer/NextUpdateButton
@onready var status_label: Label = $MarginContainer/VBoxContainer/Status
@onready var staff_container: HBoxContainer = $MarginContainer/VBoxContainer/Staff
@onready var tables_container: GridContainer = $MarginContainer/VBoxContainer/Tables

@onready var overview_label: Label = $MarginContainer/VBoxContainer/Overview
@onready var action_label: Label = $MarginContainer/VBoxContainer/Action
@onready var results_label: RichTextLabel = $MarginContainer/VBoxContainer/Results
@onready var history_toggle: CheckButton = $Footer/HistoryToggle
var staff_labels: Dictionary = {}
var table_labels: Array[Label] = []
@onready var latest_event_label: RichTextLabel = $MarginContainer/VBoxContainer/LatestEvent
var latest_event: String = ""
var table_portraits: Array[TextureRect] = []
const STAFF_PORTRAITS := {
	"Lysa": preload("res://portraits/lysa_icon.png"),
	"Brakka": preload("res://portraits/brakka_icon.png"),
	"Mimi": preload("res://portraits/mimi_icon.png"),
}
var history_lines: Array[String] = []
const HISTORY_LIMIT := 160

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
	history_toggle.toggled.connect(_on_history_toggled)
	_start_new_night()

func _start_new_night() -> void:
	phrasebook_pause_timer.stop()
	pending_lines.clear()
	playback_active = false
	_clear_choices()
	log_label.clear()
	history_lines.clear()
	latest_event = ""
	latest_event_label.clear()
	_apply_result(sim.start_new_night())

func _on_next_hour_button_pressed() -> void:
	if playback_active or sim.phase != Simulation.Phase.BETWEEN_HOURS:
		return
	_apply_result(sim.advance_hour())

func _apply_result(result: Dictionary) -> void:
	phrasebook_pause_timer.stop()
	_clear_choices()
	pending_lines.clear()
	# History is optional: presentation never waits on individual lines.
	for line in result.get("log_lines", []):
		_record_history(str(line))
	for update in result.get("phrasebook_updates", []):
		_record_history(str(update["text"]))
	if log_label.visible:
		_render_history()
	playback_active = sim.phase in [Simulation.Phase.ADMITTING, Simulation.Phase.PROCESSING]
	_show_choices(sim.pending_choices)
	_refresh_dashboard()
	if playback_active:
		phrasebook_pause_timer.start(playback_delay)


func _playback_step() -> void:
	if not playback_active:
		return
	phrasebook_pause_timer.stop()
	if sim.phase == Simulation.Phase.ADMITTING:
		_apply_result(sim.process_next_client_entry())
	elif sim.phase == Simulation.Phase.PROCESSING:
		_apply_result(sim.process_next_table())
	else:
		playback_active = false
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
	_record_history(text)
	if log_label.visible:
		_render_history()

func _record_history(text: String) -> void:
	if text.is_empty():
		return
	if not latest_event.is_empty():
		history_lines.append(latest_event)
	latest_event = text
	latest_event_label.text = text
	while history_lines.size() > HISTORY_LIMIT:
		history_lines.pop_front()

func _render_history() -> void:
	log_label.text = "\n".join(history_lines)
	log_label.scroll_to_line(maxi(0, log_label.get_line_count() - 1))

func _on_history_toggled(enabled: bool) -> void:
	log_label.visible = enabled
	if enabled:
		_render_history()


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

func _build_dashboard() -> void:
	# Build once. Stable controls retain focus and do not flicker each turn.
	for w in sim.wenches:
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label = Label.new()
		label.custom_minimum_size = Vector2(0, 80)
		panel.add_child(label)
		staff_container.add_child(panel)
		staff_labels[w["name"]] = label
	for slot in range(1, GameConfig.NUM_TABLES + 1):
		var frame = PanelContainer.new()
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var panel = VBoxContainer.new()
		frame.add_child(panel)
		var row = HBoxContainer.new()
		var indicator = preload("res://TableIndicator.tscn").instantiate()
		row.add_child(indicator)
		var portrait = TextureRect.new()
		portrait.custom_minimum_size = Vector2(48, 48)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(portrait)
		table_portraits.append(portrait)
		var label = Label.new()
		row.add_child(label)
		panel.add_child(row)
		var selector = OptionButton.new()
		selector.add_item("No assignment")
		selector.set_item_disabled(0, true)
		for w in sim.wenches:
			selector.add_item(w["name"])
			selector.set_item_metadata(selector.item_count - 1, w["name"])
		selector.item_selected.connect(_on_assignment_selected.bind(selector, slot))
		panel.add_child(selector)
		tables_container.add_child(frame)
		indicator.set_number(slot)
		hud.table_indicators.append(indicator)
		table_selectors.append(selector)
		table_labels.append(label)

func _refresh_dashboard() -> void:
	if staff_labels.is_empty():
		_build_dashboard()
	var phase_text = "Ready"
	var action_text = "Review staff assignments, then select Next Hour."
	match sim.phase:
		Simulation.Phase.CLOSED:
			phase_text = "Closed"
			action_text = "Night complete. Review the results or start a new night."
		Simulation.Phase.AWAITING_ASSIGNMENT:
			phase_text = "Assignment needed"
			action_text = "Choose a staff portrait for %s." % sim.get_next_pending_table_label()
		Simulation.Phase.ADMITTING:
			phase_text = "Guests arriving"
			action_text = "Checking arrivals…"
		Simulation.Phase.AWAITING_CHOICE:
			phase_text = "Decision needed"
			var target = sim._find_visit(sim.pending_choices[0]["visit_id"])
			action_text = "%s needs attention. Choose an action below." % target.get("label", "A table")
		Simulation.Phase.PROCESSING:
			phase_text = "Service in progress"
			action_text = "Table status updates automatically."
	var time_text = sim._get_time_string()
	if sim.hour_in_progress:
		time_text = "%s–%s · Hour %d/%d" % [sim._format_time(sim.hour), sim._format_time(sim.hour + 1), sim.hour + 1, GameConfig.HOURS_PER_NIGHT]
	else:
		time_text += " · %d/%d hours complete" % [sim.hour, GameConfig.HOURS_PER_NIGHT]
	status_label.text = "%s · %s" % [time_text, phase_text]
	action_label.text = action_text
	var guests = 0
	var unserved = 0
	for table in sim.tables:
		guests += table["group_size"]
		if table["is_unserved"]:
			unserved += 1
	var summary = sim.get_night_summary()
	overview_label.text = "Occupied: %d/%d tables    Guests: %d    Unserved: %d    Completed visits: %d" % [sim.tables.size(), GameConfig.NUM_TABLES, guests, unserved, summary["completed"]]
	for w in sim.wenches:
		var assignments: Array[String] = []
		for slot in w["assigned_tables"]:
			assignments.append(str(slot))
		var state = str(w["current_state"]).capitalize()
		if w["current_state"] == "exhausted":
			state = "Recovering · %dh left" % w["recovery_hours"]
		elif assignments.is_empty():
			state = "Available · resting"
		staff_labels[w["name"]].text = "%s · %s\nStamina: %d/%d\nTables: %s\nCharm: %d · Service: %d · Tips: %d" % [w["name"], state, w["stamina"], w["max_stamina"], "None" if assignments.is_empty() else ", ".join(assignments), w["charm"], w["service"], w["tips_earned"]]
	for slot in range(1, GameConfig.NUM_TABLES + 1):
		var table: Dictionary = {}
		for candidate in sim.tables:
			if candidate["id"] == slot:
				table = candidate
				break
		var portrait = table_portraits[slot - 1]
		var server = "" if table.is_empty() or table.get("is_unserved", true) else str(table.get("active_wench", ""))
		portrait.texture = STAFF_PORTRAITS.get(server)
		portrait.visible = portrait.texture != null
		portrait.tooltip_text = server
		var selector = table_selectors[slot - 1]
		selector.set_meta("empty_slot", table.is_empty())
		selector.set_meta("visit_id", table.get("visit_id", -1))
		selector.select(0)
		if table.is_empty():
			table_labels[slot - 1].text = "Table %d · EMPTY\nGuests: 0\nStaff: —\n" % slot
		else:
			var attention = "OCCUPIED"
			if sim.has_pending_table_assignment() and sim.pending_table_assignments[0]["visit_id"] == table["visit_id"]:
				attention = "ASSIGN STAFF"
			elif sim.phase == Simulation.Phase.AWAITING_CHOICE and sim.pending_choices[0]["visit_id"] == table["visit_id"]:
				attention = "DECISION NEEDED"
			table_labels[slot - 1].text = "Table %d · %s\nGuests: %d · Staff: %s\nSatisfaction: %d\nRowdiness: %.1f" % [slot, attention, table["group_size"], "UNSERVED" if table["is_unserved"] else table["active_wench"], table["satisfaction"], table["rowdiness"]]
		for i in range(sim.wenches.size()):
			var w = sim.wenches[i]
			selector.set_item_disabled(i + 1, w["current_state"] != "serving")
			if not table.is_empty() and table["active_wench"] == w["name"]:
				selector.select(i + 1)
	results_label.visible = sim.phase == Simulation.Phase.CLOSED
	if results_label.visible:
		var satisfaction = "N/A — no visits" if summary["visits"] == 0 else "%.1f" % summary["average_satisfaction"]
		results_label.text = "[b]%s[/b]\nCompleted: %d · Bounced: %d · Average satisfaction: %s\nSales: %d · Staff tips: %d\nRowdiest visit: %s (%.1f)" % ["Service goal met" if summary["goal_met"] else "Service goal not met", summary["completed"], summary["bounced"], satisfaction, summary["sales"], summary["tips"], summary["rowdiest_label"], summary["peak_rowdiness"]]
	else:
		results_label.clear()
	hud.update_table_indicators(sim)
	_update_controls()


func _on_assignment_selected(index: int, selector: OptionButton, slot: int) -> void:
	if playback_active or sim.phase != Simulation.Phase.BETWEEN_HOURS:
		return
	var visit_id = int(selector.get_meta("visit_id", -1))
	var table = sim._find_visit(visit_id)
	if table.is_empty() or table["id"] != slot:
		return
	var result = sim.reassign_table(visit_id, str(selector.get_item_metadata(index)))
	for line in result["log_lines"]:
		_append_line(line)
	_refresh_dashboard()

func _on_wench_selected(wench_name: String) -> void:
	if playback_active or not sim.has_pending_table_assignment():
		return
	_apply_result(sim.assign_wench_to_pending_table(wench_name, assignment_visit, assignment_night))
