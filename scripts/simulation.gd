extends Resource
class_name Simulation

var tick := 0
var wenches := []
var tables := []
var pending_choices := []

# Weighted event table
var event_table := [
	{"id": "request_refill", "weight": 6},
	{"id": "flirt_minor", "weight": 4},
	{"id": "spill_drink", "weight": 2},
	{"id": "rowdy_noise", "weight": 3},
]

# --- PUBLIC API ----------------------------------------------------------

func start_new_night() -> Dictionary:
	tick = 0
	pending_choices.clear()
	_init_wenches()
	_init_tables()

	var logs = []
	logs.append("[b]A new night begins...[/b]")
	logs.append("Your staff takes their positions around the bustling tavern.")
	
	var t1 = advance_tick()
	logs.append_array(t1["log_lines"])
	
	return {"log_lines": logs, "choices": t1["choices"]}


func advance_tick() -> Dictionary:
	tick += 1
	
	var logs = []
	var choices = []
	logs.append("[color=yellow]-- Tick %d --[/color]" % tick)

	# 1. Wench stamina update
	_update_stamina(logs)

	# 2. Table events
	for table in tables:
		var e = _roll_event_for_table(table)
		logs.append_array(_resolve_event(table, e))

	# 3. Crisis check (example: rowdy tables)
	for table in tables:
		if table["rowdiness"] >= 5:
			logs.append("[color=red]%s is getting dangerously rowdy![/color]" % table["label"])
			choices.append({
				"id": "calm_%s" % table["label"],
				"text": "Intervene personally at %s" % table["label"]
			})
			pending_choices = choices

	return {"log_lines": logs, "choices": choices}


func apply_choice(choice_id: String) -> Array:
	var logs = []

	if choice_id.begins_with("calm_"):
		logs.append("[b]You intervene at the rowdy table.[/b]")
		var table_name = choice_id.replace("calm_", "")
		for table in tables:
			if table["label"] == table_name:
				table["rowdiness"] = 0
				logs.append("The shouting dies down. The customers respect your authority.")
				break

	pending_choices.clear()
	return logs


func has_pending_choices() -> bool:
	return pending_choices.size() > 0


# --- INTERNAL SYSTEMS ----------------------------------------------------

func _update_stamina(logs):
	for w in wenches:
		w["stamina"] -= 1
		if w["stamina"] <= 0:
			logs.append("[color=orange]%s looks exhausted![/color]" % w["name"])


func _roll_event_for_table(table: Dictionary) -> String:
	var total = 0
	for evt in event_table:
		total += evt["weight"]

	var roll = randi() % total
	var sum = 0
	for evt in event_table:
		sum += evt["weight"]
		if roll < sum:
			return evt["id"]
	return event_table[0]["id"]


func _resolve_event(table: Dictionary, event_id: String) -> Array:
	var logs: Array = []

	var w = _wench_for_table(table)
	if w == null:
		logs.append("%s: No wench assigned!" % table["label"])
		return logs

	match event_id:
		"request_refill":
			logs.append("%s requests refills. %s hurries over." %
				[table["label"], w["name"]])
			logs.append_array(_event_check(w, table, 2, "quick service", "delayed service"))

		"flirt_minor":
			logs.append("%s tries to flirt with %s." %
				[table["label"], w["name"]])
			logs.append_array(_event_check(w, table, 3, "graceful deflection", "awkward moment"))

		"spill_drink":
			logs.append("%s accidentally spills a drink!" % w["name"])
			logs.append_array(_event_check(w, table, 4, "smooth recovery", "big mess"))

		"rowdy_noise":
			table["rowdiness"] += 1
			logs.append("%s starts shouting loudly. Rowdiness now %d." %
				[table["label"], table["rowdiness"]])

	return logs



func _event_check(w: Dictionary, table: Dictionary, difficulty: int, success_msg: String, fail_msg: String) -> Array:
	var logs = []
	var fatigue_penalty = int((w["max_stamina"] - w["stamina"]) / 2)
	var roll = w["charm"] + randi() % 5 - fatigue_penalty

	if roll >= difficulty:
		logs.append("Success: %s pulls off a %s." % [w["name"], success_msg])
		table["satisfaction"] += 2
	else:
		logs.append("[color=orange]Failure:[/color] %s suffers %s." %
			[w["name"], fail_msg])
		table["satisfaction"] -= 2
		table["rowdiness"] += 1

	return logs


func _wench_for_table(table: Dictionary):
	for w in wenches:
		if w["assigned_table"] == table["label"]:
			return w
	return null

# --- INITIALIZATION ------------------------------------------------------

func _init_wenches():
	wenches.clear()
	wenches.append(_make_wench("Lysa", 7, 4, 3, "Table 2"))
	wenches.append(_make_wench("Brakka", 3, 5, 8, "Table 1"))
	wenches.append(_make_wench("Mimi", 5, 8, 5, "Table 3"))


func _init_tables():
	tables.clear()
	tables.append(_make_table("Table 1", "Dwarven miners"))
	tables.append(_make_table("Table 2", "Noble couple"))
	tables.append(_make_table("Table 3", "Mercenary band"))


func _make_wench(name, charm, service, stamina, table):
	return {
		"name": name,
		"charm": charm,
		"service": service,
		"stamina": stamina,
		"max_stamina": stamina,
		"assigned_table": table,
		"traits": [],
	}


func _make_table(label, group):
	return {
		"label": label,
		"group": group,
		"satisfaction": 0,
		"patience": 5,
		"rowdiness": 0,
	}
