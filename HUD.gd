extends CanvasLayer

var cheap_ale_label: Label
var cheap_wine_label: Label
var strong_ale_label: Label
var mead_label: Label
var good_wine_label: Label
var gold_label: Label

var table_indicators: Array = []  # ← NEW: will hold our 6 TableIndicator nodes
var wench_selector = null  # Reference to WenchSelector UI component

func _ready() -> void:
	# Try to find labels using get_node_or_null for better error handling
	cheap_ale_label = get_node_or_null("Control/MarginContainer/VBoxContainer/CheapAleLabel")
	cheap_wine_label = get_node_or_null("Control/MarginContainer/VBoxContainer/CheapWineLabel")
	strong_ale_label = get_node_or_null("Control/MarginContainer/VBoxContainer/StrongAleLabel")
	mead_label = get_node_or_null("Control/MarginContainer/VBoxContainer/MeadLabel")
	good_wine_label = get_node_or_null("Control/MarginContainer/VBoxContainer/GoodWineLabel")
	gold_label = get_node_or_null("Control/MarginContainer/VBoxContainer/GoldLabel")
	
	# Debug: Print what we found
	if not cheap_ale_label:
		push_error("HUD: CheapAleLabel not found at path: Control/MarginContainer/VBoxContainer/CheapAleLabel")
		print("HUD node children: ", get_children())
	if not cheap_wine_label:
		push_error("HUD: CheapWineLabel not found!")
	if not strong_ale_label:
		push_error("HUD: StrongAleLabel not found!")
	if not mead_label:
		push_error("HUD: MeadLabel not found!")
	if not good_wine_label:
		push_error("HUD: GoodWineLabel not found!")

	# ---- NEW: hook up TableIndicators ----
	# Adjust this path if you put the container somewhere else, e.g.:
	# "Control/MarginContainer/VBoxContainer/TableIndicators"
	var indicators_parent := get_node_or_null("TableIndicators")
	if indicators_parent == null:
		push_error("HUD: TableIndicators container not found at path: TableIndicators")
		print("HUD children: ", get_children())  # Debug print
	else:
		# Clear just in case
		table_indicators.clear()
		
		# We expect children named TableIndicator1..6
		for i in range(1, 7):  # 1 to 6
			var node_name := "TableIndicator%d" % i
			var indicator = indicators_parent.get_node_or_null(node_name)
			if indicator:
				table_indicators.append(indicator)
				# Tell the indicator what its table number is (for the big number label)
				if indicator.has_method("set_number"):
					indicator.set_number(i)
			else:
				push_error("HUD: %s not found under Control/TableIndicators" % node_name)
	
	# ---- Hook up WenchSelector ----
	wench_selector = get_node_or_null("WenchSelector")
	if wench_selector == null:
		push_warning("HUD: WenchSelector not found. Make sure it's added as a child of HUD in Main.tscn")


func update_liquor(stock: Dictionary) -> void:
	# stock expected like:
	# { "cheap_ale": 23, "cheap_wine": 19, "strong_ale": 17, "mead": 15, "good_wine": 12 }
	if cheap_ale_label:
		cheap_ale_label.text  = "Cheap ale: %d"   % stock.get("cheap_ale", 0)
	if cheap_wine_label:
		cheap_wine_label.text = "Cheap wine: %d"  % stock.get("cheap_wine", 0)
	if strong_ale_label:
		strong_ale_label.text = "Strong ale: %d"  % stock.get("strong_ale", 0)
	if mead_label:
		mead_label.text       = "Mead: %d"        % stock.get("mead", 0)
	if good_wine_label:
		good_wine_label.text  = "Good wine: %d"   % stock.get("good_wine", 0)


func update_gold(amount: int) -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % amount


# ---- NEW: update_table_indicators(sim) ----
func update_table_indicators(sim) -> void:
	# Safety: if we somehow have no indicators, just bail out
	if table_indicators.is_empty():
		return

	# 1) First mark ALL as empty
	for indicator in table_indicators:
		if indicator and indicator.has_method("set_empty"):
			indicator.set_empty()

	# 2) Fill with occupied tables from the Simulation
	# sim.tables is expected to be an Array of Dictionaries, each with a "label" like "Table 1"
	for table_data in sim.tables:
		var label: String = table_data.get("label", "")
		if not label.begins_with("Table "):
			continue

		# Extract the number after "Table "
		# "Table 1" -> "1"
		var number_str := label.substr(6)  # from index 6 to the end
		var table_num := int(number_str)   # 1..6

		var idx := table_num - 1           # convert to 0..5
		if idx < 0 or idx >= table_indicators.size():
			continue

		var indicator = table_indicators[idx]
		if indicator == null:
			continue

		var rowdiness: float = table_data.get("rowdiness", 0.0)
		var wench_name: String = table_data.get("active_wench", "")
		var is_unserved: bool = table_data.get("is_unserved", false)

		if indicator.has_method("set_occupied"):
			indicator.set_occupied()
		if indicator.has_method("set_rowdiness"):
			indicator.set_rowdiness(rowdiness, GameConfig.ROWDINESS_DANGEROUS)
		if indicator.has_method("set_wench"):
			indicator.set_wench(wench_name)
		if indicator.has_method("set_unserved"):
			indicator.set_unserved(is_unserved)


# ---- WenchSelector management ----
func update_wench_selector(sim) -> void:
	if wench_selector == null:
		return
	
	# Update wench availability based on their states
	if wench_selector.has_method("update_wench_availability"):
		wench_selector.update_wench_availability(sim.wenches)
	
	# Show/hide selector based on pending table assignment
	var has_pending = sim.has_pending_table_assignment()
	if wench_selector:
		wench_selector.visible = has_pending

func highlight_selected_wench(wench_name: String) -> void:
	if wench_selector == null:
		return
	
	if wench_selector.has_method("highlight_wench"):
		wench_selector.highlight_wench(wench_name)
