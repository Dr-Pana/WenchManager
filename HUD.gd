extends CanvasLayer

var cheap_ale_label: Label
var cheap_wine_label: Label
var strong_ale_label: Label
var mead_label: Label
var good_wine_label: Label
var gold_label: Label

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
