# scripts/main.gd
extends Control

# Grab references to UI elements
@onready var hud = $HUD
@onready var log_label: RichTextLabel = $MarginContainer/VBoxContainer/Log
@onready var choices_container: VBoxContainer = $MarginContainer/VBoxContainer/Choices
@onready var new_night_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/NewNightButton
@onready var next_hour_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/NextTickButton
var next_update_button: Button

var sim: Simulation
var pending_phrasebook_updates: Array = []  # Array of Dictionary
var pending_choices_after_updates: Array = []  # Store choices to show after phrasebook updates
var phrasebook_display_mode: String = "pause"  # "pause" or "button"
var phrasebook_pause_timer: Timer

func _ready() -> void:
	sim = Simulation.new()
	# Connect to simulation signals
	sim.liquor_stock_changed.connect(_on_liquor_stock_changed)
	sim.gold_changed.connect(_on_gold_changed)
	
	# Create timer for pause mode
	phrasebook_pause_timer = Timer.new()
	phrasebook_pause_timer.wait_time = 1.0  # 1 second pause between phrasebook updates
	phrasebook_pause_timer.one_shot = true
	phrasebook_pause_timer.autostart = false
	phrasebook_pause_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	phrasebook_pause_timer.timeout.connect(_display_next_phrasebook_update)
	add_child(phrasebook_pause_timer)
	
	# Get reference to next update button
	next_update_button = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/NextUpdateButton")
	
	_connect_buttons()
	_start_new_night()

func _connect_buttons() -> void:
	new_night_button.pressed.connect(_on_new_night_button_pressed)
	next_hour_button.pressed.connect(_on_next_hour_button_pressed)
	if next_update_button:
		next_update_button.pressed.connect(_on_next_update_button_pressed)
		next_update_button.visible = false


func _on_liquor_stock_changed(stock: Dictionary) -> void:
	hud.update_liquor(stock)


func _on_gold_changed(new_gold: int) -> void:
	hud.update_gold(new_gold)


func _start_new_night() -> void:
	_clear_log()
	_clear_choices()
	pending_phrasebook_updates.clear()
	pending_choices_after_updates.clear()
	if phrasebook_pause_timer:
		phrasebook_pause_timer.stop()
	if next_update_button:
		next_update_button.visible = false
	var result: Dictionary = sim.start_new_night()
	_apply_result(result)


func _on_new_night_button_pressed() -> void:
	_start_new_night()


func _on_next_hour_button_pressed() -> void:
	# Optional: prevent skipping ahead if a choice is unresolved
	if sim.has_pending_choices():
		_append_line("[color=red]Resolve the current choice before advancing time.[/color]")
		return

	var result: Dictionary = sim.advance_hour()
	_apply_result(result)


func _apply_result(result: Dictionary) -> void:
	var logs: Array = result.get("log_lines", [])
	var choices: Array = result.get("choices", [])
	var phrasebook_updates: Array = result.get("phrasebook_updates", [])

	for line in logs:
		_append_line(line)

	# Handle phrasebook updates
	if phrasebook_updates.size() > 0:
		# If timer is running, append to existing updates instead of replacing
		if phrasebook_pause_timer.time_left > 0:
			pending_phrasebook_updates.append_array(phrasebook_updates)
			# Don't call _display_next_phrasebook_update() - let the timer handle it
		else:
			pending_phrasebook_updates = phrasebook_updates
			pending_choices_after_updates = choices  # Store choices to show after updates
			_display_next_phrasebook_update()
	else:
		_show_choices(choices)


# --- Choices handling ----------------------------------------------------------

func _show_choices(choices: Array) -> void:
	_clear_choices()

	for choice_dict in choices:
		if not choice_dict.has("id") or not choice_dict.has("text"):
			continue

		var btn := Button.new()
		btn.text = str(choice_dict["text"])
		var choice_id := str(choice_dict["id"])

		# Bind the choice_id so we know which one was clicked
		btn.pressed.connect(_on_choice_button_pressed.bind(choice_id))

		choices_container.add_child(btn)


func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()


func _on_choice_button_pressed(choice_id: String) -> void:
	var result: Dictionary = sim.apply_choice(choice_id)
	_apply_result(result)


# --- Logging helpers -----------------------------------------------------------

func _append_line(text: String) -> void:
	if log_label.text.is_empty():
		log_label.text = text
	else:
		log_label.text += "\n" + text
	log_label.scroll_to_line(log_label.get_line_count() - 1)


func _clear_log() -> void:
	log_label.clear()


# --- Phrasebook update display system -------------------------------------

func _display_next_phrasebook_update() -> void:
	if pending_phrasebook_updates.size() == 0:
		# All updates displayed, show choices if any
		var choices_to_show = pending_choices_after_updates.duplicate()
		pending_choices_after_updates.clear()
		_show_choices(choices_to_show)
		if next_update_button:
			next_update_button.visible = false
		
		# If no choices and hour is in progress, auto-continue to next table
		# But only if timer is not running (all phrasebook updates have been displayed)
		if choices_to_show.size() == 0 and sim.hour_in_progress and phrasebook_pause_timer.time_left <= 0:
			# Auto-continue to next table
			var result: Dictionary = sim.process_next_table()
			_apply_result(result)
		return
	
	var update = pending_phrasebook_updates.pop_front()
	_append_line(update["text"])
	
	if pending_phrasebook_updates.size() > 0:
		# More updates to show - always pause 1 second between updates
		# Stop timer first to ensure clean restart
		phrasebook_pause_timer.stop()
		# Reset wait time to ensure it's set correctly
		phrasebook_pause_timer.wait_time = 1.0
		phrasebook_pause_timer.start()
		# Debug: print to verify timer is starting
		print("Timer started, time_left: ", phrasebook_pause_timer.time_left)
		# Return here - don't process choices or auto-continue yet
		return
	
	# Last update displayed - wait a moment before showing choices/auto-continuing
	# This ensures the last update is visible before moving on
	if phrasebook_display_mode == "button" and next_update_button:
		next_update_button.visible = false
	
	# Show choices immediately
	var choices_to_show = pending_choices_after_updates.duplicate()
	pending_choices_after_updates.clear()
	_show_choices(choices_to_show)
	
	# If no choices and hour is in progress, wait a bit then auto-continue to next table
	# Use a small delay to ensure the last phrasebook update is visible
	if choices_to_show.size() == 0 and sim.hour_in_progress:
		# Temporarily disconnect the normal handler and connect auto-continue
		if phrasebook_pause_timer.timeout.is_connected(_display_next_phrasebook_update):
			phrasebook_pause_timer.timeout.disconnect(_display_next_phrasebook_update)
		phrasebook_pause_timer.timeout.connect(_auto_continue_to_next_table, CONNECT_ONE_SHOT)
		phrasebook_pause_timer.stop()
		phrasebook_pause_timer.wait_time = 1.0
		phrasebook_pause_timer.start()
		print("Auto-continue timer started")



func _auto_continue_to_next_table() -> void:
	print("Auto-continue timer fired")
	# Disconnect this handler
	if phrasebook_pause_timer.timeout.is_connected(_auto_continue_to_next_table):
		phrasebook_pause_timer.timeout.disconnect(_auto_continue_to_next_table)
	# Reconnect the normal timeout handler
	if not phrasebook_pause_timer.timeout.is_connected(_display_next_phrasebook_update):
		phrasebook_pause_timer.timeout.connect(_display_next_phrasebook_update)
	# Auto-continue to next table
	var result: Dictionary = sim.process_next_table()
	_apply_result(result)


func _on_next_update_button_pressed() -> void:
	if next_update_button:
		next_update_button.visible = false
	_display_next_phrasebook_update()
