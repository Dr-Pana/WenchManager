extends Control

signal wench_selected(wench_name: String)

# References to the three portrait buttons
@onready var lysa_button: Button = $HBoxContainer/LysaButton
@onready var brakka_button: Button = $HBoxContainer/BrakkaButton
@onready var mimi_button: Button = $HBoxContainer/MimiButton

# References to the portrait textures (for visual feedback)
@onready var lysa_portrait: TextureRect = $HBoxContainer/LysaButton/Portrait
@onready var brakka_portrait: TextureRect = $HBoxContainer/BrakkaButton/Portrait
@onready var mimi_portrait: TextureRect = $HBoxContainer/MimiButton/Portrait

# References to the name labels
@onready var lysa_label: Label = $HBoxContainer/LysaButton/NameLabel
@onready var brakka_label: Label = $HBoxContainer/BrakkaButton/NameLabel
@onready var mimi_label: Label = $HBoxContainer/MimiButton/NameLabel

# Store original modulate colors for visual feedback
var original_modulate = Color(1, 1, 1, 1)
var selected_modulate = Color(1.2, 1.2, 1.0, 1)  # Slightly brighter/yellow tint when selected
var unavailable_modulate = Color(0.5, 0.5, 0.5, 0.7)  # Grayed out when unavailable

func _ready() -> void:
	# Connect button signals
	if lysa_button:
		lysa_button.pressed.connect(_on_lysa_pressed)
	if brakka_button:
		brakka_button.pressed.connect(_on_brakka_pressed)
	if mimi_button:
		mimi_button.pressed.connect(_on_mimi_pressed)
	
	# Set initial button text
	if lysa_label:
		lysa_label.text = "Lysa"
	if brakka_label:
		brakka_label.text = "Brakka"
	if mimi_label:
		mimi_label.text = "Mimi"

func _on_lysa_pressed() -> void:
	wench_selected.emit("Lysa")

func _on_brakka_pressed() -> void:
	wench_selected.emit("Brakka")

func _on_mimi_pressed() -> void:
	wench_selected.emit("Mimi")

# Update visual state of wenches based on availability
func update_wench_availability(wenches: Array) -> void:
	# Create a dictionary for quick lookup
	var wench_states = {}
	for wench in wenches:
		if typeof(wench) == TYPE_DICTIONARY:
			var name = wench.get("name", "")
			var state = wench.get("current_state", "serving")
			wench_states[name] = state
	
	# Update each button's appearance
	_update_button_state(lysa_button, lysa_portrait, "Lysa", wench_states)
	_update_button_state(brakka_button, brakka_portrait, "Brakka", wench_states)
	_update_button_state(mimi_button, mimi_portrait, "Mimi", wench_states)

func _update_button_state(button: Button, portrait: TextureRect, wench_name: String, wench_states: Dictionary) -> void:
	if not button or not portrait:
		return
	
	var state = wench_states.get(wench_name, "serving")
	
	# If wench is available (serving state), enable button and show normal appearance
	if state == "serving":
		button.disabled = false
		portrait.modulate = original_modulate
	else:
		# If wench is unavailable (exhausted, socializing, injured), disable button and gray out
		button.disabled = true
		portrait.modulate = unavailable_modulate

# Show visual feedback when a wench is selected (brief highlight)
func highlight_wench(wench_name: String) -> void:
	var portrait: TextureRect = null
	match wench_name:
		"Lysa":
			portrait = lysa_portrait
		"Brakka":
			portrait = brakka_portrait
		"Mimi":
			portrait = mimi_portrait
	
	if portrait:
		# Create a tween for brief highlight
		var tween = create_tween()
		tween.tween_property(portrait, "modulate", selected_modulate, 0.2)
		tween.tween_property(portrait, "modulate", original_modulate, 0.2)

