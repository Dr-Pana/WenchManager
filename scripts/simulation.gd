extends Resource
class_name Simulation

signal liquor_stock_changed(stock: Dictionary)
signal gold_changed(new_gold: int)

var hour := 0
var gold: int = 0
var wenches := []
var tables := []
var pending_choices := []
var stock := {}  # Stock levels for each liquor type (in pints)
var phrasebook_templates: Array[String] = []  # Loaded phrasebook templates

# Table-by-table processing state
var current_hour_tables: Array = []  # Randomized table order for current hour
var current_table_index: int = -1  # Which table is currently being processed
enum Phase { BETWEEN_HOURS, PROCESSING, AWAITING_CHOICE, CLOSED }
var phase: Phase = Phase.CLOSED
var hour_in_progress: bool:
	get:
		return phase == Phase.PROCESSING or phase == Phase.AWAITING_CHOICE
var night_serial: int = 0
var next_visit_id: int = 1
var visit_history: Array = []
var hour_workloads: Dictionary = {}
var rng := RandomNumberGenerator.new()
var narration_rng := RandomNumberGenerator.new()

# Configuration is now in scripts/game_config.gd
# Access via GameConfig.CONSTANT_NAME

# --- PUBLIC API ----------------------------------------------------------

func start_new_night(seed_value: int = -1) -> Dictionary:
	night_serial += 1
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	narration_rng.seed = rng.seed
	hour = 0
	gold = 0
	phase = Phase.BETWEEN_HOURS
	pending_choices.clear()
	current_hour_tables.clear()
	current_table_index = -1
	visit_history.clear()
	hour_workloads.clear()
	next_visit_id = 1
	_load_phrasebook()
	_init_stock()
	_init_wenches()
	tables.clear()
	liquor_stock_changed.emit(stock)
	gold_changed.emit(gold)
	var logs = ["[b]A new night begins at 5pm.[/b]", "Your staff takes their positions around the empty tavern.",
		"Goal: complete at least %d visits with average departure satisfaction of %.1f or better." % [GameConfig.TARGET_COMPLETED_VISITS, GameConfig.TARGET_SATISFACTION]]
	_append_stock_report(logs)
	return _result(logs)


func advance_hour() -> Dictionary:
	if phase != Phase.BETWEEN_HOURS:
		return _result()
	phase = Phase.PROCESSING
	var logs = ["[color=yellow]-- Hour %d (%s–%s) --[/color]" % [hour + 1, _format_time(hour), _format_time(hour + 1)]]
	logs.append_array(_attempt_client_entry(_generate_clients_for_hour(hour + 1)))
	_refresh_coverage()
	hour_workloads.clear()
	for w in wenches:
		hour_workloads[w["name"]] = w["assigned_tables"].size()
	current_hour_tables = tables.duplicate()
	for i in range(current_hour_tables.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = current_hour_tables[i]
		current_hour_tables[i] = current_hour_tables[j]
		current_hour_tables[j] = temp
	current_table_index = 0
	var result = process_next_table()
	result["log_lines"] = logs + result["log_lines"]
	return result


func process_next_table() -> Dictionary:
	if phase != Phase.PROCESSING:
		return _result()
	while current_table_index < current_hour_tables.size():
		var visit_id = current_hour_tables[current_table_index]["visit_id"]
		current_table_index += 1
		var table = _find_visit(visit_id)
		if table.is_empty():
			continue
		var before_satisfaction = table["satisfaction"]
		var before_rowdiness = table["rowdiness"]
		_apply_unserved_penalties_for_table(table)
		_update_table_rowdiness_for_table(table)
		var event_id = _roll_event_for_table(table)
		var event_text = ""
		if event_id != "":
			event_text = _resolve_event(table, event_id)
		table["peak_rowdiness"] = max(table["peak_rowdiness"], table["rowdiness"])
		var updates = []
		var narrative = _generate_phrasebook_update_for_table(table)
		if not narrative.is_empty():
			updates.append(narrative)
		var outcome = "%s: satisfaction %+d → %d; rowdiness %+.1f → %.1f." % [table["label"], table["satisfaction"] - before_satisfaction, table["satisfaction"], table["rowdiness"] - before_rowdiness, table["rowdiness"]]
		updates.append({"text": event_text + " " + outcome if event_text != "" else outcome})
		if table["rowdiness"] >= GameConfig.ROWDINESS_FISTFIGHT:
			updates.append({"text": "[color=red]%s must be cleared by the bouncers.[/color]" % table["label"]})
			pending_choices = [_choice("bounce", "Acknowledge (table cleared)", table)]
		elif table["rowdiness"] >= GameConfig.ROWDINESS_DANGEROUS:
			updates.append({"text": "[color=orange]%s needs your attention.[/color]" % table["label"]})
			pending_choices = [_choice("free_round", "Free round on the house", table), _choice("bouncer", "Step in personally", table), _choice("ignore", "Ignore", table)]
		if has_pending_choices():
			phase = Phase.AWAITING_CHOICE
		return _result([], updates)
	return _finish_hour()


func apply_choice(choice_id: String) -> Dictionary:
	if phase != Phase.AWAITING_CHOICE:
		return _result()
	var selected: Dictionary = {}
	for choice in pending_choices:
		if choice["id"] == choice_id:
			selected = choice
			break
	if selected.is_empty():
		return _result()
	var table = _find_visit(selected["visit_id"])
	if table.is_empty():
		return _result()
	var logs = []
	match selected["action"]:
		"bounce":
			logs.append("%s is cleared; its tips are forfeited." % table["label"])
			_archive_visit(table, "bounced")
		"free_round":
			# Comp the current round: its inventory was already deducted.
			var refund = table["hourly_consumption"] * GameConfig.LIQUOR_PRICES.get(table["liquor_preference"], 1)
			if table["hourly_consumption"] > 0:
				gold -= refund
				gold_changed.emit(gold)
				table["satisfaction"] += GameConfig.FREE_ROUND_SATISFACTION_BONUS
				table["rowdiness"] += GameConfig.FREE_ROUND_ROWDINESS_REDUCTION
				logs.append("%s: current round comped (%d gold refunded); satisfaction +2, rowdiness -3." % [table["label"], refund])
			else:
				logs.append("%s: nothing was served, so no round could be comped." % table["label"])
		"bouncer":
			table["satisfaction"] += GameConfig.BOUNCER_SATISFACTION_PENALTY
			table["rowdiness"] += GameConfig.BOUNCER_ROWDINESS_REDUCTION
			logs.append("%s: you step in; satisfaction -1, rowdiness -2." % table["label"])
		"ignore":
			logs.append("%s: you leave the situation alone." % table["label"])
	_update_table_event_chance(table)
	pending_choices.clear()
	phase = Phase.PROCESSING
	# Continuation belongs to the controller; do not process another table here.
	return _result(logs)


func has_pending_choices() -> bool:
	return pending_choices.size() > 0


# --- HELPER FUNCTIONS ----------------------------------------------------

func _get_wench_mood(wench, _table: Dictionary) -> String:
	if wench == null:
		return "tired"
	
	var stamina = wench.get("stamina", 0)
	var max_stamina = wench.get("max_stamina", 1)
	var stamina_percent = float(stamina) / float(max_stamina) if max_stamina > 0 else 0.0
	
	# Count how many tables this wench is actively serving
	var active_table_count = 0
	var wench_name = wench.get("name", "")
	for t in tables:
		if t.get("active_wench", "") == wench_name:
			active_table_count += 1
	
	# Determine mood based on stamina and workload
	if stamina_percent <= GameConfig.STAMINA_EXHAUSTED:
		return "exhausted"
	elif stamina_percent <= GameConfig.STAMINA_WEARY:
		return "weary"
	elif stamina_percent <= GameConfig.STAMINA_TIRED:
		if active_table_count > 1:
			return "stressed"
		else:
			return "tired"
	elif stamina_percent <= GameConfig.STAMINA_FOCUSED:
		if active_table_count > 1:
			return "focused"
		else:
			return "cheerful"
	elif stamina_percent <= GameConfig.STAMINA_CHEERFUL:
		if active_table_count > 1:
			return "cheerful"
		else:
			return "energetic"
	else:
		return "energetic"


func _generate_phrasebook_update_for_table(table: Dictionary) -> Dictionary:
	# Generate phrasebook update for a single table
	if phrasebook_templates.size() == 0:
		return {}
	
	if typeof(table) != TYPE_DICTIONARY:
		return {}
	
	# Randomly select a template
	var template = phrasebook_templates[narration_rng.randi() % phrasebook_templates.size()]
	
	# Get wench for this table
	var wench = _wench_for_table(table)
	var wench_name = table.get("active_wench", "No one")
	if wench == null:
		return {"text": "%s is unserved; customers are waiting." % table["label"]}
	else:
		wench_name = wench.get("name", "No one")
	
	# Fill placeholders
	var text = template
	text = text.replace("{table}", table.get("label", "Unknown Table"))
	text = text.replace("{amount}", str(table.get("hourly_consumption", 0)))
	text = text.replace("{liquor}", table.get("liquor_preference", "cheap ale"))
	text = text.replace("{wench}", wench_name)
	
	# Get mood
	var mood = _get_wench_mood(wench, table)
	text = text.replace("{state}", mood)
	
	return {
		"table": table,
		"text": text
	}


func _get_liquor_for_status(social_status: String) -> String:
	return GameConfig.SOCIAL_STATUS_LIQUOR.get(social_status.to_lower(), "cheap ale")


func _liquor_key_from_preference(pref: String) -> String:
	match pref:
		"cheap ale":
			return "cheap_ale"
		"cheap wine":
			return "cheap_wine"
		"strong ale":
			return "strong_ale"
		"mead":
			return "mead"
		"good wine":
			return "good_wine"
		_:
			return "cheap_ale" # fallback


func _get_time_string() -> String:
	return _format_time(hour)

func _format_time(completed_hours: int) -> String:
	var hour_24 = (GameConfig.STARTING_HOUR + completed_hours) % 24
	var hour_12 = hour_24 % 12
	if hour_12 == 0:
		hour_12 = 12
	return "%d%s" % [hour_12, "am" if hour_24 < 12 else "pm"]


func _get_race_compatibility_modifier(wench_race: String, client_race: String) -> int:
	var wench_race_lower = wench_race.to_lower()
	var client_race_lower = client_race.to_lower()
	
	if GameConfig.RACE_COMPATIBILITY.has(wench_race_lower):
		var client_map = GameConfig.RACE_COMPATIBILITY[wench_race_lower]
		return client_map.get(client_race_lower, 0)
	return 0


func _get_size_description(group_size: int) -> String:
	if group_size == GameConfig.GROUP_SIZE_SINGLE:
		return "single"
	elif group_size == GameConfig.GROUP_SIZE_SMALL:
		return "small"
	elif group_size <= GameConfig.GROUP_SIZE_MEDIUM:
		return "medium"
	else:
		return "large"


func _get_rowdiness_description(rowdiness: int) -> String:
	if rowdiness <= GameConfig.ROWDINESS_CALM:
		return "calm"
	elif rowdiness <= GameConfig.ROWDINESS_MODERATE:
		return "moderate"
	elif rowdiness <= GameConfig.ROWDINESS_ROWDY:
		return "rowdy"
	else:
		return "very rowdy"


func _random_social_status() -> String:
	# Weighted random selection
	return _weighted_random(GameConfig.SOCIAL_STATUS_WEIGHTS)


func _random_race() -> String:
	# Equal chance for each race
	return GameConfig.AVAILABLE_RACES[rng.randi() % GameConfig.AVAILABLE_RACES.size()]


func _random_group_size() -> int:
	# Weighted towards smaller groups (1-6 people)
	var roll = rng.randf()
	for size in GameConfig.GROUP_SIZE_DISTRIBUTION.keys():
		if roll < GameConfig.GROUP_SIZE_DISTRIBUTION[size]:
			return size
	return 6  # Fallback to max size


func _weighted_random(weights: Dictionary) -> String:
	var total = 0
	for key in weights:
		total += weights[key]
	
	var roll = rng.randi() % total
	var sum = 0
	for key in weights:
		sum += weights[key]
		if roll < sum:
			return key
	return weights.keys()[0]  # Fallback


func _update_table_event_chance(table: Dictionary) -> void:
	# Recalculate event chance when rowdiness changes
	# Clamp rowdiness to 0+ (allow values up to ROWDINESS_FISTFIGHT+ for fistfight trigger)
	if table.has("rowdiness"):
		table["rowdiness"] = max(table["rowdiness"], 0.0)
		var chance = float(table["rowdiness"]) / GameConfig.EVENT_CHANCE_DIVISOR
		if table.get("is_unserved", false):
			chance *= GameConfig.UNSERVED_EVENT_CHANCE_MULTIPLIER
		table["event_chance"] = clampf(chance, 0.0, 1.0)
		
		# Update description to reflect current rowdiness
		var rowdiness_int = int(table["rowdiness"])
		var rowdiness_desc = _get_rowdiness_description(rowdiness_int)
		var size_desc = _get_size_description(table.get("group_size", 1))
		var social_status = table.get("social_status", "unknown")
		var race = table.get("race", "unknown")
		table["description"] = "A %s group of %s %s %s" % [
			size_desc,
			rowdiness_desc,
			social_status,
			race + "s"
		]


# --- INTERNAL SYSTEMS ----------------------------------------------------

func _update_staff_after_hour() -> Array:
	var logs = []
	for w in wenches:
		if w["current_state"] == "exhausted":
			w["recovery_hours"] -= 1
			if w["recovery_hours"] <= 0:
				w["current_state"] = "serving"
				w["stamina"] = w["max_stamina"]
				logs.append("%s has recovered and is available again." % w["name"])
			continue
		var count = hour_workloads.get(w["name"], 0)
		if count == 0:
			w["stamina"] = min(w["max_stamina"], w["stamina"] + GameConfig.IDLE_STAMINA_RECOVERY)
			continue
		var drain = GameConfig.BASE_STAMINA_DRAIN + (count - 1) * GameConfig.OVERWORK_STAMINA_DRAIN_PER_TABLE
		w["stamina"] = max(0, w["stamina"] - drain)
		if w["stamina"] == 0:
			w["current_state"] = "exhausted"
			w["recovery_hours"] = GameConfig.EXHAUSTION_RECOVERY_HOURS
			logs.append("%s is exhausted and will rest for %d hours." % [w["name"], w["recovery_hours"]])
	return logs


func _update_table_rowdiness_for_table(table: Dictionary) -> void:
	# Update rowdiness for a single table based on:
	# 1. Race modifier (orcs rowdiest, then dwarves, etc.)
	# 2. Drunkenness (consumption over time)
	# 3. Group size (0.3 per person as rate modifier)
	if not table.has("rowdiness"):
		return
	
	var race = table.get("race", "human")
	var group_size = table.get("group_size", 1)
	var consumption = table.get("consumption", 0)  # Track how much they've consumed (in pints)
	
	# Race modifier (orcs = 0.4, dwarves = 0.3, etc.)
	var race_modifier = GameConfig.RACE_ROWDINESS_MODIFIER.get(race, 0.15)
	
	# Group size modifier per person per hour
	var group_size_modifier = group_size * GameConfig.GROUP_SIZE_ROWDINESS_MODIFIER
	
	# Consumption: pints per person per hour, modified by social status
	# Formula: pints_per_hour = ceil(group_size * base_rate)
	var social_status = table.get("social_status", "poor")
	var base_rate = GameConfig.SOCIAL_STATUS_BASE_DRAIN.get(social_status, 1.0)
	var pints_per_hour = int(ceil(group_size * base_rate))  # At least 1 pint per hour for the group
	var liquor_pref = table.get("liquor_preference", "cheap ale")
	var key := _liquor_key_from_preference(liquor_pref)
	
	# Deduct from stock (integer pints)
	var actual_consumption = 0
	if table.get("is_unserved", false):
		pass
	elif stock.has(key) and stock[key] > 0:
		actual_consumption = min(pints_per_hour, stock[key])
		stock[key] -= actual_consumption
		stock[key] = max(stock[key], 0)
		consumption += actual_consumption
		
		# Calculate and add upfront payment for this consumption
		var base_price = GameConfig.LIQUOR_PRICES.get(liquor_pref, 1)
		var upfront_payment = actual_consumption * base_price
		gold += upfront_payment
		gold_changed.emit(gold)
		
		# Check if we ran out
		if actual_consumption < pints_per_hour:
			# No logging - information will come through phrasebook updates
			table["satisfaction"] += GameConfig.OUT_OF_STOCK_SATISFACTION_PENALTY
			table["rowdiness"] += GameConfig.OUT_OF_STOCK_ROWDINESS_PENALTY
	else:
		# Out of stock - customers are unhappy
		# No logging - information will come through phrasebook updates
		table["satisfaction"] += GameConfig.COMPLETELY_OUT_OF_STOCK_SATISFACTION_PENALTY
		table["rowdiness"] += GameConfig.COMPLETELY_OUT_OF_STOCK_ROWDINESS_PENALTY
	
	# Store hourly consumption for phrasebook
	table["hourly_consumption"] = actual_consumption
	table["consumption"] = consumption
	var drunkenness_modifier = consumption * GameConfig.DRUNKENNESS_ROWDINESS_MODIFIER
	
	# Total rowdiness increase per hour
	var rowdiness_increase = race_modifier + group_size_modifier + drunkenness_modifier
	
	# Apply increase
	table["rowdiness"] += rowdiness_increase
	_update_table_event_chance(table)
	
	# Emit signal after this table is processed
	liquor_stock_changed.emit(stock)


func _roll_event_for_table(table: Dictionary) -> String:
	if typeof(table) != TYPE_DICTIONARY:
		return GameConfig.DEFAULT_EVENT_WEIGHTS[0]["id"]

	# Check if an event should occur based on rowdiness
	var event_chance = table.get("event_chance", 0.0)
	if rng.randf() > event_chance:
		return ""  # No event this tick

	var weights = _event_table_for_group(table.get("group", ""))

	var total = 0
	for evt in weights:
		total += evt["weight"]

	var roll = rng.randi() % total
	var sum = 0
	for evt in weights:
		sum += evt["weight"]
		if roll < sum:
			return evt["id"]
	return weights[0]["id"]


func _resolve_event(table: Dictionary, event_id: String) -> String:
	if event_id == "rowdy_noise":
		table["rowdiness"] += GameConfig.ROWDY_NOISE_ROWDINESS_PENALTY
		_update_table_event_chance(table)
		return "%s: noisy guests increase rowdiness." % table["label"]
	var w = _wench_for_table(table)
	if w == null or w["current_state"] != "serving":
		return "%s: no staff member is available to handle the request." % table["label"]
	match event_id:
		"request_refill":
			return _event_check(w, table, GameConfig.EVENT_DIFFICULTY_REQUEST_REFILL, "quick service", "delayed service", "service")
		"flirt_minor":
			return _event_check(w, table, GameConfig.EVENT_DIFFICULTY_FLIRT_MINOR, "graceful deflection", "awkward moment", "charm")
		"spill_drink":
			return _event_check(w, table, GameConfig.EVENT_DIFFICULTY_SPILL_DRINK, "smooth recovery", "big mess", "service")
	return ""


func _event_check(w: Dictionary, table: Dictionary, difficulty: int, success_msg: String, fail_msg: String, stat: String = "charm") -> String:
	# Return the resolved outcome so the controller can explain state changes.
	
	var fatigue_penalty = int((w["max_stamina"] - w["stamina"]) / 2)
	
	# Calculate overwork penalty: count tables where wench is active_wench
	var active_table_count = 0
	var wench_name = w.get("name", "")
	for t in tables:
		if t.get("active_wench", "") == wench_name:
			active_table_count += 1
	
	# Overwork difficulty modifier per extra table
	var overwork_difficulty = 0
	if active_table_count > 1:
		overwork_difficulty = (active_table_count - 1) * GameConfig.OVERWORK_DIFFICULTY_PER_TABLE
	
	# Service efficiency penalty per extra table
	var efficiency_multiplier = 1.0
	if active_table_count > 1:
		efficiency_multiplier = 1.0 - (GameConfig.SERVICE_EFFICIENCY_PENALTY_PER_TABLE * (active_table_count - 1))
	
	# Apply race compatibility modifier
	var race_modifier = _get_race_compatibility_modifier(w.get("race", "human"), table.get("race", "human"))
	
	var roll = w[stat] + rng.randi() % 5 - fatigue_penalty + race_modifier
	var adjusted_difficulty = difficulty + overwork_difficulty

	if roll >= adjusted_difficulty:
		# Apply service efficiency penalty to satisfaction gains
		var satisfaction_gain = int(GameConfig.EVENT_SUCCESS_BASE_SATISFACTION * efficiency_multiplier)
		table["satisfaction"] += satisfaction_gain
		return "%s: %s — %s succeeds (%s)." % [table["label"], w["name"], success_msg, stat]
	else:
		table["satisfaction"] += GameConfig.EVENT_FAIL_SATISFACTION_PENALTY
		table["rowdiness"] += GameConfig.EVENT_FAIL_ROWDINESS_PENALTY
		_update_table_event_chance(table)

	return "%s: %s — %s (%s check failed)." % [table["label"], w["name"], fail_msg, stat]


func _wench_for_table(table: Dictionary) -> Variant:
	if typeof(table) != TYPE_DICTIONARY:
		return null
	
	var active_wench_name = table.get("active_wench", "")
	if active_wench_name == "":
		return null

	for w in wenches:
		if w["name"] == active_wench_name:
			return w
	return null


func _check_wench_availability_for_table(table: Dictionary) -> void:
	var w = _wench_for_table(table)
	if w != null and w["current_state"] == "serving":
		table["is_unserved"] = false
		return
	table["active_wench"] = ""
	table["is_unserved"] = true
	_assign_wench_to_new_table(table)


func _apply_unserved_penalties_for_table(table: Dictionary) -> void:
	if table.get("is_unserved", false):
		table["rowdiness"] += GameConfig.UNSERVED_ROWDINESS_PENALTY
		table["satisfaction"] += GameConfig.UNSERVED_SATISFACTION_PENALTY
		_update_table_event_chance(table)


func _event_table_for_group(group: String) -> Array:
	if GameConfig.GROUP_EVENT_WEIGHTS.has(group):
		return GameConfig.GROUP_EVENT_WEIGHTS[group]
	return GameConfig.DEFAULT_EVENT_WEIGHTS


func _generate_clients_for_hour(hour: int) -> Array:
	# Generate client data for the specified hour based on pattern
	# Returns array of dictionaries with social_status, race, group_size
	var client_count = GameConfig.CLIENTS_PER_HOUR.get(hour, 0)
	var clients = []
	
	for i in range(client_count):
		var social_status = _random_social_status()
		var race = _random_race()
		var group_size = _random_group_size()
		clients.append({
			"social_status": social_status,
			"race": race,
			"group_size": group_size,
		})
	
	return clients


func _attempt_client_entry(clients: Array) -> Array:
	# Attempt to have clients enter the tavern
	# Returns array of log messages for entries
	var logs = []
	
	for client in clients:
		# Check if there's space available
		if tables.size() >= GameConfig.NUM_TABLES:
			# No tables available, skip coinflip
			continue
		
		# 50% chance to enter
		if rng.randf() < GameConfig.CLIENT_ENTRY_CHANCE:
			# Client enters - create a table
			var next_table_id = _first_empty_slot()
			var label = "Table %d" % next_table_id
			var table = _make_table(
				next_table_id,
				label,
				client["social_status"],
				client["race"],
				client["group_size"]
			)
			
			# Assign available staff by current workload
			_assign_wench_to_new_table(table)
			
			tables.append(table)
			_sync_assignments()
			logs.append("%s enters and sits at %s." % [table.get("description", "A group"), label])
	
	return logs


func _assign_wench_to_new_table(table: Dictionary) -> void:
	# Choose the available staff member with the smallest workload
	# Find wenches that are available (state == "serving")
	var available_wenches = []
	for w in wenches:
		if w.get("current_state", "serving") == "serving":
			available_wenches.append(w)
	
	if available_wenches.size() == 0:
		# No available wenches, mark as unserved
		table["is_unserved"] = true
		return
	
	# Count how many tables each wench is currently serving
	var wench_table_counts = {}
	for w in available_wenches:
		wench_table_counts[w["name"]] = 0
		for t in tables:
			if t.get("active_wench", "") == w["name"]:
				wench_table_counts[w["name"]] += 1
	
	# Find wench with fewest tables (load balancing)
	var best_wench = null
	var min_tables = 999999
	for w in available_wenches:
		var count = wench_table_counts.get(w["name"], 0)
		if count < min_tables:
			min_tables = count
			best_wench = w
	
	if best_wench != null:
		table["active_wench"] = best_wench["name"]
		table["is_unserved"] = false

	else:
		table["is_unserved"] = true


func _process_table_leaving() -> Array:
	var logs = []
	for table in tables.duplicate():
		table["hours_occupied"] += 1
		var leave_chance = minf(1.0, GameConfig.LEAVE_CHANCE_BASE + max(0, table["hours_occupied"] - 1) * GameConfig.LEAVE_CHANCE_INCREMENT)
		if hour + 1 >= GameConfig.HOURS_PER_NIGHT or rng.randf() < leave_chance:
			var tips = _calculate_table_tips(table)
			var w = _wench_for_table(table)
			if w != null:
				w["tips_earned"] += tips
				logs.append("%s leaves, paying %d gold in tips to %s." % [table["label"], tips, w["name"]])
			else:
				logs.append("%s leaves without tips (no staff assigned)." % table["label"])
			_archive_visit(table, "completed")
	return logs


func _calculate_night_summary() -> Array:
	var summary = get_night_summary()
	var logs = ["", "[b]--- End of Night Summary ---[/b]"]
	if summary["visits"] == 0:
		logs.append("No customer visits tonight. Service goal not met.")
	else:
		logs.append("Completed visits: %d | Bounced: %d" % [summary["completed"], summary["bounced"]])
		logs.append("Average departure satisfaction (all visits): %.1f" % summary["average_satisfaction"])
		logs.append("[b]%s[/b]" % ("Service goal met!" if summary["goal_met"] else "Service goal not met — try another night."))
		logs.append("Rowdiest visit: %s (peak %.1f)" % [summary["rowdiest_label"], summary["peak_rowdiness"]])
	logs.append("Sales: %d gold | Staff tips: %d gold" % [gold, summary["tips"]])
	for w in wenches:
		logs.append("%s: %d tips, %d/%d stamina (%s)." % [w["name"], w["tips_earned"], w["stamina"], w["max_stamina"], w["current_state"]])
	return logs

func get_night_summary() -> Dictionary:
	var total_satisfaction: float = 0.0
	var completed: int = 0
	var bounced: int = 0
	var peak: float = -1.0
	var rowdiest: String = "None"
	for visit in visit_history:
		total_satisfaction += visit["satisfaction"]
		if visit["departure_reason"] == "completed":
			completed += 1
		else:
			bounced += 1
		if visit["peak_rowdiness"] > peak:
			peak = visit["peak_rowdiness"]
			rowdiest = "%s, visit %d" % [visit["label"], visit["visit_id"]]
	var average: float = total_satisfaction / visit_history.size() if not visit_history.is_empty() else 0.0
	var tips: int = 0
	for w in wenches:
		tips += w["tips_earned"]
	return {"visits": visit_history.size(), "completed": completed, "bounced": bounced,
		"average_satisfaction": average, "peak_rowdiness": maxf(0.0, peak), "rowdiest_label": rowdiest,
		"sales": gold, "tips": tips, "goal_met": phase == Phase.CLOSED and completed >= GameConfig.TARGET_COMPLETED_VISITS and average >= GameConfig.TARGET_SATISFACTION}


func _calculate_table_tips(table: Dictionary) -> int:
	# Calculate tips for a table when they leave
	# Formula: consumption * base_price * (1 + satisfaction / SATISFACTION_TIPS_DIVISOR)
	# Note: Tips are now paid to waitresses, not added to gold total
	var consumption = table.get("consumption", 0)  # in pints
	var satisfaction = table.get("satisfaction", 0)
	var liquor_pref = table.get("liquor_preference", "cheap ale")
	var base_price = GameConfig.LIQUOR_PRICES.get(liquor_pref, 1)
	
	var tips = consumption * base_price * (1.0 + float(satisfaction) / GameConfig.SATISFACTION_TIPS_DIVISOR)
	return maxi(0, int(tips))


func _load_phrasebook() -> void:
	phrasebook_templates.clear()
	var file = FileAccess.open("res://phrasebook.md", FileAccess.READ)
	if file == null:
		push_error("Failed to open phrasebook.md")
		return
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		# Lines starting with quotes (straight or curly) are templates
		if line.length() > 0:
			# Check if line starts and ends with quote characters (handles both " and "")
			var quote_chars = ["\"", "\u201C", "\u201D", "\u201E", "\u201F"]  # Various quote types
			var first_char = line[0]
			var last_char = line[line.length() - 1]
			if first_char in quote_chars and last_char in quote_chars:
				# Remove surrounding quotes
				var template = line.substr(1, line.length() - 2)
				if template.length() > 0:
					phrasebook_templates.append(template)
	
	file.close()
	
	if phrasebook_templates.size() == 0:
		push_warning("No phrasebook templates loaded! Check phrasebook.md file format.")


func _init_stock():
	# Initialize starting stock for each liquor type (in pints)
	# Values from GameConfig.STARTING_STOCK
	stock = GameConfig.STARTING_STOCK.duplicate()


func _append_stock_report(logs: Array) -> void:
	logs.append("")
	logs.append("[b]--- Stock Report ---[/b]")
	for liquor_type in stock.keys():
		var display_name = liquor_type.replace("_", " ").capitalize()
		logs.append("%s: %d pints" % [display_name, stock[liquor_type]])
	logs.append("")


func _init_wenches():
	wenches.clear()
	wenches.append(_make_wench("Lysa", 7, 4, 3, [], "elf"))
	wenches.append(_make_wench("Brakka", 3, 5, 8, [], "human"))
	wenches.append(_make_wench("Mimi", 5, 8, 5, [], "tiefling"))


func _make_wench(name, charm, service, stamina, assigned_tables, race = "human"):
	return {
		"name": name,
		"charm": charm,
		"service": service,
		"stamina": stamina,
		"max_stamina": stamina,
		"assigned_tables": assigned_tables,
		"current_state": "serving",
		"recovery_hours": 0,
		"traits": [],
		"race": race,
		"tips_earned": 0,  # Track tips earned by this wench
	}


func _make_table(id: int, label: String, social_status: String, race: String, group_size: int):
	var visit_id = next_visit_id
	next_visit_id += 1
	# Derive liquor preference from social status
	var liquor_preference = _get_liquor_for_status(social_status)
	
	# Rowdiness starts at 0 and increases per hour
	var rowdiness = 0
	var event_chance = 0.0
	
	# Calculate resource drain rate
	var base_rate = GameConfig.SOCIAL_STATUS_BASE_DRAIN.get(social_status, 1.0)
	var size_modifier = 1.0
	if group_size > 2:
		size_modifier = 1.0 + (group_size - 2) * GameConfig.GROUP_SIZE_DRAIN_MODIFIER
	var resource_drain_rate = base_rate * size_modifier
	
	# Generate description (e.g., "A small group of noble dwarves")
	# Note: rowdiness description will be updated dynamically as rowdiness increases
	var size_desc = _get_size_description(group_size)
	var description = "A %s group of %s %s" % [
		size_desc,
		social_status,
		race + "s"
	]
	
	# Calculate attitude modifier (will be computed dynamically based on assigned wench)
	# For now, store the race for compatibility lookup
	var attitude_modifiers = {
		"towards": race,  # This is the client race
		"value": 0  # Will be computed when wench is assigned
	}
	
	return {
		"id": id,
		"visit_id": visit_id,
		"peak_rowdiness": 0.0,
		"label": label,
		"group": description,  # Keep for backward compatibility
		"social_status": social_status,
		"race": race,
		"group_size": group_size,
		"rowdiness": rowdiness,
		"consumption": 0,  # Track consumption/drunkenness (in pints)
		"liquor_preference": liquor_preference,
		"event_chance": event_chance,
		"resource_drain_rate": resource_drain_rate,
		"attitude_modifiers": attitude_modifiers,
		"description": description,
		"satisfaction": 0,
		"patience": GameConfig.STARTING_PATIENCE,
		"active_wench": "",
		"is_unserved": false,
		"hourly_consumption": 0,  # Track consumption for this hour (for phrasebook)
		"hours_occupied": 0,  # Track how many hours this table has been occupied
	}


func _result(logs: Array = [], updates: Array = []) -> Dictionary:
	return {"log_lines": logs, "choices": pending_choices.duplicate(true), "phrasebook_updates": updates}

func _choice(action: String, text: String, table: Dictionary) -> Dictionary:
	return {"id": "%d:%d:%d:%s" % [night_serial, hour, table["visit_id"], action],
		"text": text, "action": action, "visit_id": table["visit_id"]}

func _find_visit(visit_id: int) -> Dictionary:
	for table in tables:
		if table["visit_id"] == visit_id:
			return table
	return {}

func _first_empty_slot() -> int:
	for slot in range(1, GameConfig.NUM_TABLES + 1):
		var occupied = false
		for table in tables:
			if table["id"] == slot:
				occupied = true
				break
		if not occupied:
			return slot
	return -1

func _archive_visit(table: Dictionary, reason: String) -> void:
	# Removing by visit identity avoids collisions when a slot is reused.
	for i in range(tables.size()):
		if tables[i]["visit_id"] == table["visit_id"]:
			var record = table.duplicate(true)
			record["departure_reason"] = reason
			visit_history.append(record)
			tables.remove_at(i)
			_sync_assignments()
			return

func _sync_assignments() -> void:
	for w in wenches:
		w["assigned_tables"] = []
	for table in tables:
		for w in wenches:
			if table["active_wench"] == w["name"]:
				w["assigned_tables"].append(table["id"])

func _refresh_coverage() -> void:
	for table in tables:
		_check_wench_availability_for_table(table)
	_sync_assignments()

func reassign_table(visit_id: int, wench_name: String) -> Dictionary:
	if phase != Phase.BETWEEN_HOURS:
		return _result()
	var table = _find_visit(visit_id)
	if table.is_empty():
		return _result()
	for w in wenches:
		if w["name"] == wench_name and w["current_state"] == "serving":
			table["active_wench"] = wench_name
			table["is_unserved"] = false
			_sync_assignments()
			return _result(["%s is now assigned to %s." % [wench_name, table["label"]]])
	return _result()

func _finish_hour() -> Dictionary:
	if phase != Phase.PROCESSING:
		return _result()
	var logs = _process_table_leaving()
	logs.append_array(_update_staff_after_hour())
	hour += 1
	current_hour_tables.clear()
	current_table_index = -1
	phase = Phase.CLOSED if hour >= GameConfig.HOURS_PER_NIGHT else Phase.BETWEEN_HOURS
	_refresh_coverage()
	if phase == Phase.CLOSED:
		logs.append_array(_calculate_night_summary())
	return _result(logs)
