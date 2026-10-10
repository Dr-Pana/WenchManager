extends Control
## Counter-first presentation: the simulation owns all transactions and time.
const PORTRAITS := {
	"Lysa": preload("res://portraits/lysa_icon.png"),
	"Brakka": preload("res://portraits/brakka_icon.png"),
	"Mimi": preload("res://portraits/mimi_icon.png"),
}
const PRODUCTS := ["cheap ale", "cheap wine", "strong ale", "mead", "good wine"]
const SHORT_NAMES := ["Cheap ale", "Cheap wine", "Strong ale", "Mead", "Good wine"]
const INK := Color("f0e3cb")
const GOLD := Color("ddb36b")
const MUTED := Color("adaba2")
var sim := Simulation.new()
var floor_view: Control
var clock: Label
var wallet: Label
var progress: ProgressBar
var staff_cards: Dictionary = {}
var shelf_buttons: Array[Button] = []
var coin_buttons: Array[Button] = []
var ticket: Label
var host_portrait: TextureRect
var host_name: Label
var tray_art: Control
var tray_label: Label
var change_label: Label
var feedback: Label
var table_detail: Label
var prompt: Label
var latest: RichTextLabel
var history: RichTextLabel
var summary: Label
var next_button: Button
var serve_button: Button
var clear_button: Button
var skip_button: Button
var order_controls: VBoxContainer
var decision_title: Label
var choices: VBoxContainer
var timer: Timer
var tray: Dictionary = {}
var change_coins: Array[int] = []
var order_id := ""
var selected_slot := 1
var history_lines: Array[String] = []
var latest_text := ""
var restart_dialog: ConfirmationDialog

func _ready() -> void:
	_build_theme()
	_build_ui()
	timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.5
	timer.timeout.connect(_step)
	add_child(timer)
	sim.counter_service_enabled = true
	_start_night()

func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", INK)
	theme.set_color("default_color", "RichTextLabel", MUTED)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var color := Color("293438")
		if state == "hover": color = Color("40504e")
		if state == "pressed": color = Color("566052")
		if state == "disabled": color = Color("242829")
		var style := box(color, 10)
		style.set_content_margin_all(8)
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = GOLD
			style.set_border_width_all(2)
		theme.set_stylebox(state, "Button", style)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color("757b78"))
	var bar_background := box(Color("121a1e"), 4)
	bar_background.set_content_margin_all(0)
	var bar_fill := box(Color("91af9e"), 4)
	bar_fill.set_content_margin_all(0)
	theme.set_stylebox("background", "ProgressBar", bar_background)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)

func box(color: Color, radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(16)
	return style

func label(parent: Node, text: String, font_size: int = 16, color: Color = INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

func button(parent: Node, text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func panel(parent: Node, color: Color = Color("202a2e")) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", box(color))
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	frame.add_child(contents)
	return contents

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("111b20")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var branding := VBoxContainer.new()
	branding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(branding)
	label(branding, "WENCH MANAGER", 13, GOLD)
	label(branding, "Behind the bar", 32)
	clock = label(header, "17:00", 24, GOLD)
	wallet = label(header, "   SALES  0", 22)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 5
	progress.show_percentage = false
	progress.max_value = 8
	root.add_child(progress)
	# Scroll the main body while keeping the clock and primary controls reachable.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	scroll.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.3
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	var room := panel(left, Color("332925"))
	floor_view = preload("res://ui/counter/tavern_floor.gd").new()
	floor_view.portraits = PORTRAITS
	floor_view.table_selected.connect(_select_table)
	room.add_child(floor_view)
	table_detail = label(room, "", 15)
	table_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label(left, "YOUR STAFF   /   Select a portrait to assign", 13, GOLD)
	var roster := HBoxContainer.new()
	roster.add_theme_constant_override("separation", 10)
	left.add_child(roster)
	for staff_name in PORTRAITS:
		var card := panel(roster)
		var portrait_button := button(card, staff_name, _assign.bind(staff_name))
		portrait_button.icon = PORTRAITS[staff_name]
		portrait_button.expand_icon = true
		portrait_button.add_theme_constant_override("icon_max_width", 50)
		portrait_button.custom_minimum_size.y = 74
		var stamina := ProgressBar.new()
		stamina.custom_minimum_size.y = 10
		stamina.show_percentage = false
		card.add_child(stamina)
		var detail := label(card, "", 13, MUTED)
		staff_cards[staff_name] = {"button": portrait_button, "bar": stamina, "detail": detail}
	var events := panel(left)
	label(events, "LATEST EVENT", 12, GOLD)
	latest = RichTextLabel.new()
	latest.bbcode_enabled = true
	latest.custom_minimum_size.y = 48
	events.add_child(latest)
	var history_button := button(events, "Show earlier events", _toggle_history)
	history_button.tooltip_text = "Recent descriptions from this night"
	history = RichTextLabel.new()
	history.bbcode_enabled = true
	history.custom_minimum_size.y = 130
	history.visible = false
	events.add_child(history)
	var counter := panel(body, Color("2b3030"))
	counter.get_parent().custom_minimum_size.x = 490
	label(counter, "THE COUNTER", 13, GOLD)
	var arrival := HBoxContainer.new()
	counter.add_child(arrival)
	host_portrait = TextureRect.new()
	host_portrait.custom_minimum_size = Vector2(56, 60)
	host_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	host_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrival.add_child(host_portrait)
	host_name = label(arrival, "The counter is quiet", 22)
	var paper := panel(counter, Color("ddd0b4"))
	ticket = label(paper, "", 16, Color("342e27"))
	ticket.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order_controls = VBoxContainer.new()
	order_controls.add_theme_constant_override("separation", 6)
	counter.add_child(order_controls)
	label(order_controls, "1  ·  FILL THE TRAY", 13, GOLD)
	var shelves := HBoxContainer.new()
	shelves.add_theme_constant_override("separation", 6)
	order_controls.add_child(shelves)
	for i in PRODUCTS.size():
		var shelf := button(shelves, "", _add_product.bind(PRODUCTS[i]))
		shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shelf.add_theme_font_size_override("font_size", 12)
		shelf.custom_minimum_size = Vector2(75, 104)
		shelf.icon = load("res://art/%s.svg" % PRODUCTS[i].replace(" ", "_"))
		shelf.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shelf.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		shelf.expand_icon = true
		shelf.add_theme_constant_override("icon_max_width", 28)
		shelf.tooltip_text = "%s · %d gold each · keyboard %d" % [PRODUCTS[i].capitalize(), GameConfig.LIQUOR_PRICES[PRODUCTS[i]], i + 1]
		shelf_buttons.append(shelf)
	tray_art = preload("res://ui/counter/service_tray.gd").new()
	tray_art.item_removed.connect(_remove_product)
	order_controls.add_child(tray_art)
	tray_label = label(order_controls, "Empty tray", 14)
	tray_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label(order_controls, "2  ·  COUNT OUT CHANGE", 13, GOLD)
	var coins := HBoxContainer.new()
	order_controls.add_child(coins)
	for denomination in [1, 2, 5]:
		var coin := button(coins, "●  %d" % denomination, _add_coin.bind(denomination))
		coin.custom_minimum_size = Vector2(68, 46)
		coin.add_theme_color_override("font_color", GOLD)
		coin_buttons.append(coin)
	button(coins, "Undo coin", _undo_coin)
	change_label = label(order_controls, "Change tray: 0", 16)
	feedback = label(order_controls, "", 14, Color("e6b778"))
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	order_controls.add_child(actions)
	serve_button = button(actions, "Serve & settle  ↵", _serve)
	serve_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button = button(actions, "Clear tray", _clear_tray)
	skip_button = button(order_controls, "Cannot serve · return payment", _skip)
	skip_button.tooltip_text = "No sale; no stock used. The table receives the normal shortage penalty."
	decision_title = label(counter, "TABLE DECISIONS", 13, GOLD)
	choices = VBoxContainer.new()
	counter.add_child(choices)
	summary = label(counter, "", 17)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	root.add_child(footer)
	prompt = label(footer, "", 16)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	serve_button.reparent(footer)
	serve_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	next_button = button(footer, "Open the doors  →", _next_hour)
	button(footer, "New night", _request_restart)
	restart_dialog = ConfirmationDialog.new()
	restart_dialog.dialog_text = "Start a new night? This night's progress will be cleared."
	restart_dialog.confirmed.connect(_start_night)
	add_child(restart_dialog)

func _start_night() -> void:
	timer.stop()
	history_lines.clear()
	latest_text = ""
	tray.clear()
	change_coins.clear()
	order_id = ""
	selected_slot = 1
	feedback.text = ""
	_apply(sim.start_new_night())

func _request_restart() -> void:
	if sim.hour == 0 and sim.phase == Simulation.Phase.BETWEEN_HOURS or sim.phase == Simulation.Phase.CLOSED:
		_start_night()
	else:
		restart_dialog.popup_centered()

func _apply(result: Dictionary) -> void:
	timer.stop()
	for line in result.get("log_lines", []):
		_record(str(line))
	for update in result.get("phrasebook_updates", []):
		_record(str(update["text"]))
	if sim.phase == Simulation.Phase.AWAITING_ASSIGNMENT:
		selected_slot = sim.pending_table_assignments[0]["id"]
	if not sim.pending_order.is_empty() and order_id != sim.pending_order["id"]:
		order_id = sim.pending_order["id"]
		selected_slot = sim.pending_order["slot"]
		tray.clear()
		change_coins.clear()
		feedback.text = "Click stock to prepare the order, then count out change."
	if sim.phase != Simulation.Phase.AWAITING_ORDER:
		order_id = ""
		tray.clear()
		change_coins.clear()
	_refresh()
	if sim.phase in [Simulation.Phase.ADMITTING, Simulation.Phase.PROCESSING]:
		timer.start()

func _record(text: String) -> void:
	if text.is_empty(): return
	if not latest_text.is_empty(): history_lines.append(latest_text)
	while history_lines.size() > 160: history_lines.pop_front()
	latest_text = text
	latest.text = text
	history.text = "\n".join(history_lines)

func _step() -> void:
	if sim.phase == Simulation.Phase.ADMITTING:
		_apply(sim.process_next_client_entry())
	elif sim.phase == Simulation.Phase.PROCESSING:
		_apply(sim.process_next_table())

func _next_hour() -> void:
	_apply(sim.advance_hour())

func _select_table(slot: int) -> void:
	selected_slot = slot
	_refresh()

func _assign(staff_name: String) -> void:
	if sim.has_pending_table_assignment():
		_apply(sim.assign_wench_to_pending_table(staff_name, sim.pending_table_assignments[0]["visit_id"], sim.night_serial))
	elif sim.phase == Simulation.Phase.BETWEEN_HOURS:
		for table in sim.tables:
			if table["id"] == selected_slot:
				_apply(sim.reassign_table(table["visit_id"], staff_name))
				return

func _add_product(product: String) -> void:
	if sim.phase != Simulation.Phase.AWAITING_ORDER: return
	var available: int = sim.stock.get(sim._liquor_key_from_preference(product), 0)
	if tray.get(product, 0) < available and _tray_count() < 24:
		tray[product] = tray.get(product, 0) + 1
	_refresh_tray()

func _remove_product(product: String) -> void:
	if sim.phase == Simulation.Phase.AWAITING_ORDER and tray.get(product, 0) > 0:
		tray[product] -= 1
		_refresh_tray()

func _tray_count() -> int:
	var total := 0
	for quantity in tray.values(): total += int(quantity)
	return total

func _add_coin(value: int) -> void:
	if sim.phase != Simulation.Phase.AWAITING_ORDER: return
	if _change_total() + value <= sim.pending_order["tender"]:
		change_coins.append(value)
	_refresh_tray()

func _change_total() -> int:
	var total := 0
	for value in change_coins: total += value
	return total

func _undo_coin() -> void:
	if not change_coins.is_empty(): change_coins.pop_back()
	_refresh_tray()

func _clear_tray() -> void:
	tray.clear()
	change_coins.clear()
	_refresh_tray()

func _serve() -> void:
	if sim.phase != Simulation.Phase.AWAITING_ORDER: return
	var result := sim.submit_counter_order(order_id, tray, _change_total())
	if not result.get("accepted", false):
		feedback.text = result.get("error", "Check the order.")
		return
	feedback.text = "Order delivered. Payment settled."
	_apply(result)

func _skip() -> void:
	if sim.phase == Simulation.Phase.AWAITING_ORDER:
		_apply(sim.submit_counter_order(order_id, {}, 0, true))

func _toggle_history() -> void:
	history.visible = not history.visible

func _refresh_tray() -> void:
	tray_art.items = tray
	tray_art.coins = change_coins
	tray_art.queue_redraw()
	var pieces: Array[String] = []
	for product in tray:
		if tray[product] > 0: pieces.append("%d × %s" % [tray[product], product])
	tray_label.text = "Tray: " + ("empty" if pieces.is_empty() else ", ".join(pieces))
	change_label.text = "Change tray: %d gold  ·  %d coins" % [_change_total(), change_coins.size()]
	for i in PRODUCTS.size():
		var stock: int = sim.stock.get(sim._liquor_key_from_preference(PRODUCTS[i]), 0)
		shelf_buttons[i].disabled = sim.phase != Simulation.Phase.AWAITING_ORDER or tray.get(PRODUCTS[i], 0) >= stock

func _refresh() -> void:
	clock.text = "%s  /  %d of 8 hours" % [sim._format_time(sim.hour), sim.hour]
	wallet.text = "   SALES  %d" % sim.gold
	progress.value = sim.hour
	var active := sim.phase == Simulation.Phase.AWAITING_ORDER
	next_button.disabled = sim.phase != Simulation.Phase.BETWEEN_HOURS
	next_button.text = "Open the doors  →" if sim.hour == 0 else "Next hour  →"
	order_controls.visible = active
	decision_title.visible = sim.has_pending_choices()
	serve_button.visible = active
	serve_button.disabled = not active
	clear_button.disabled = not active
	skip_button.disabled = not active
	for coin in coin_buttons: coin.disabled = not active
	var selected: Dictionary = {}
	for table in sim.tables:
		if table["id"] == selected_slot: selected = table
	table_detail.text = "Table %d · Empty. Click a table to inspect it." % selected_slot
	if not selected.is_empty():
		table_detail.text = "Table %d  ·  %s\n%s  ·  Satisfaction %+d  ·  Rowdiness %.1f / 15" % [selected_slot, selected["description"], selected["active_wench"] if not selected["is_unserved"] else "Unserved", selected["satisfaction"], selected["rowdiness"]]
	floor_view.tables = sim.tables
	floor_view.selected_slot = selected_slot
	floor_view.attention_slot = sim.pending_order.get("slot", -1)
	if sim.has_pending_table_assignment(): floor_view.attention_slot = sim.pending_table_assignments[0]["id"]
	if sim.has_pending_choices():
		floor_view.attention_slot = sim._find_visit(sim.pending_choices[0]["visit_id"]).get("id", -1)
	floor_view.queue_redraw()
	for w in sim.wenches:
		var card: Dictionary = staff_cards[w["name"]]
		card["bar"].max_value = w["max_stamina"]
		card["bar"].value = w["stamina"]
		card["detail"].text = "%d / %d stamina\n%s" % [w["stamina"], w["max_stamina"], "Resting · %dh" % w["recovery_hours"] if w["current_state"] == "exhausted" else "%d tables · %d tips" % [w["assigned_tables"].size(), w["tips_earned"]]]
		card["button"].disabled = w["current_state"] != "serving" or not (sim.has_pending_table_assignment() or sim.phase == Simulation.Phase.BETWEEN_HOURS and not selected.is_empty())
	for i in PRODUCTS.size():
		var amount: int = sim.stock.get(sim._liquor_key_from_preference(PRODUCTS[i]), 0)
		shelf_buttons[i].text = "%s\n%d g\n%d left" % [SHORT_NAMES[i], GameConfig.LIQUOR_PRICES[PRODUCTS[i]], amount]
	if active:
		var o := sim.pending_order
		host_portrait.texture = PORTRAITS.get(o["server"])
		host_name.text = "%s · Table %d" % [o["server"], o["slot"]]
		var available := mini(o["quantity"], sim.stock.get(o["stock_key"], 0))
		ticket.text = "ORDER  %02d\n%d × %s   @ %d gold\nBill: %d   ·   Payment received: %d\nReturn %d gold in change." % [sim.receipts.size() + 1, o["quantity"], o["product"].capitalize(), o["unit_price"], available * o["unit_price"], o["tender"], o["tender"] - available * o["unit_price"]]
		if available < o["quantity"]:
			ticket.text += "\nShort stock: supply %d; refund the rest." % available
	else:
		host_portrait.texture = null
		host_name.text = "The counter is quiet"
		ticket.text = "Orders arrive here during service.\nChoose a server for new guests on the left.\nStock and coins move when you settle an order."
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	for choice in sim.pending_choices:
		button(choices, choice["text"], func(): _apply(sim.apply_choice(choice["id"])))
	match sim.phase:
		Simulation.Phase.BETWEEN_HOURS: prompt.text = "Arrange staff, then advance the hour."
		Simulation.Phase.AWAITING_ASSIGNMENT: prompt.text = "Table %d needs a server. Select a staff portrait." % sim.pending_table_assignments[0]["id"]
		Simulation.Phase.AWAITING_ORDER: prompt.text = "Prepare the order and return change. Time is paused."
		Simulation.Phase.AWAITING_CHOICE: prompt.text = "A table needs your decision at the counter."
		Simulation.Phase.CLOSED: prompt.text = "Doors closed. Your night's results are at the counter."
		_: prompt.text = "Service in progress…"
	summary.visible = sim.phase == Simulation.Phase.CLOSED
	if summary.visible:
		var s := sim.get_night_summary()
		summary.text = "%s\n%d completed · %d bounced\nAverage satisfaction %.1f\n%d sales · %d staff tips\n%d counter orders settled" % ["SERVICE GOAL MET" if s["goal_met"] else "NIGHT COMPLETE", s["completed"], s["bounced"], s["average_satisfaction"], s["sales"], s["tips"], sim.receipts.size()]
	_refresh_tray()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or restart_dialog.visible: return
	if event.keycode >= KEY_1 and event.keycode <= KEY_5:
		_add_product(PRODUCTS[event.keycode - KEY_1])
	elif event.keycode == KEY_Q: _add_coin(1)
	elif event.keycode == KEY_W: _add_coin(2)
	elif event.keycode == KEY_E: _add_coin(5)
	elif event.keycode == KEY_BACKSPACE: _undo_coin()
	elif event.keycode == KEY_ENTER: _serve()
	elif event.keycode == KEY_SPACE and sim.phase == Simulation.Phase.BETWEEN_HOURS: _next_hour()
	else: return
	get_viewport().set_input_as_handled()
