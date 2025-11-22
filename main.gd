# scripts/main.gd
extends Control

# Grab references to UI elements
@onready var log_label: RichTextLabel = $MarginContainer/VBoxContainer/Log
@onready var choices_container: VBoxContainer = $MarginContainer/VBoxContainer/Choices
@onready var new_night_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/NewNightButton
@onready var next_tick_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/NextTickButton

var sim: Simulation

func _ready() -> void:
	sim = Simulation.new()
	_connect_buttons()
	_start_new_night()

func _connect_buttons() -> void:
	new_night_button.pressed.connect(_on_new_night_button_pressed)
	next_tick_button.pressed.connect(_on_next_tick_button_pressed)


func _start_new_night() -> void:
	_clear_log()
	_clear_choices()
	var result: Dictionary = sim.start_new_night()
	_apply_result(result)


func _on_new_night_button_pressed() -> void:
	_start_new_night()


func _on_next_tick_button_pressed() -> void:
	# Optional: prevent skipping ahead if a choice is unresolved
	if sim.has_pending_choices():
		_append_line("[color=red]Resolve the current choice before advancing time.[/color]")
		return

	var result: Dictionary = sim.advance_tick()
	_apply_result(result)


func _apply_result(result: Dictionary) -> void:
	var logs: Array = result.get("log_lines", [])
	var choices: Array = result.get("choices", [])

	for line in logs:
		_append_line(line)

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
	var logs: Array = sim.apply_choice(choice_id)
	for line in logs:
		_append_line(line)
	_clear_choices()


# --- Logging helpers -----------------------------------------------------------

func _append_line(text: String) -> void:
	if log_label.text.is_empty():
		log_label.text = text
	else:
		log_label.text += "\n" + text
	log_label.scroll_to_line(log_label.get_line_count() - 1)


func _clear_log() -> void:
	log_label.clear()
