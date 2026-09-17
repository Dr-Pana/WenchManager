extends Control

@onready var bg: ColorRect = $ColorRect
@onready var number_label: Label = $NumberLabel
@onready var wench_label: Label = $WenchLabel

var table_number: int = 0

func set_number(num: int) -> void:
	table_number = num
	number_label.text = str(num)

func set_empty() -> void:
	# Grey, semi-transparent, no wench name
	bg.color = Color(0.2, 0.2, 0.2)
	wench_label.text = ""
	modulate = Color(1, 1, 1, 0.4)  # faded

func set_occupied() -> void:
	# Full opacity when occupied
	modulate = Color(1, 1, 1, 1)

func set_rowdiness(rowdiness: float, dangerous_threshold: float) -> void:
	# Pick color based on rowdiness
	if rowdiness < 5.0:
		# calm
		bg.color = Color(0.1, 0.4, 0.1)
	elif rowdiness < dangerous_threshold:
		# rowdy
		bg.color = Color(0.6, 0.5, 0.1)
	else:
		# dangerous
		bg.color = Color(0.6, 0.1, 0.1)

func set_wench(name: String) -> void:
	if name.is_empty():
		wench_label.text = ""
	else:
		# Just show initials or first 3 letters
		wench_label.text = name.substr(0, 3)

func set_unserved(is_unserved: bool) -> void:
	# Optional: if table is unserved, add a subtle tint or an exclamation
	if is_unserved:
		# Slightly desaturate or brighten to signal "attention"
		modulate = Color(1.1, 0.9, 0.9, 1)  # pale
		# You could instead add a "!" to the name:
		wench_label.text = "!"
	else:
		# Reset to normal if you changed anything special here
		pass
