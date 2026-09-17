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
var hour_in_progress: bool = false  # Whether we're mid-hour processing

# Pending table assignment for manual wench selection
var pending_table_assignments: Array = []  # Array of tables waiting for wench assignment

# Client entry queue for processing clients one at a time
var pending_client_queue: Array = []  # Array of clients waiting to enter the tavern

# Configuration is now in scripts/game_config.gd
# Access via GameConfig.CONSTANT_NAME

# --- PUBLIC API ----------------------------------------------------------

func start_new_night() -> Dictionary:
	hour = 0
	gold = 0
	pending_choices.clear()
	# Reset table-by-table processing state
	current_hour_tables.clear()
	current_table_index = -1
	hour_in_progress = false
	# Clear pending table assignments
	pending_table_assignments.clear()
	# Clear pending client queue
	pending_client_queue.clear()
	_load_phrasebook()
	_init_stock()
	_init_wenches()
	# Start with empty tavern - no tables initially
	tables.clear()
	
	# Emit initial stock values to HUD
	liquor_stock_changed.emit(stock)
	gold_changed.emit(gold)

	var logs = []
	logs.append("[b]A new night begins at 5pm...[/b]")
	logs.append("Your staff takes their positions around the empty tavern.")
	_append_stock_report(logs)
	# No table overview since tavern starts empty
	
	return {"log_lines": logs, "choices": [], "phrasebook_updates": []}


func advance_hour() -> Dictionary:
	# Should not be called if hour is already in progress
	if hour_in_progress:
		push_error("advance_hour() called while hour is already in progress")
		return {"log_lines": [], "choices": [], "phrasebook_updates": []}
	
	# BEFORE processing tables: Generate clients for this hour and attempt entry
	# Note: hour hasn't been incremented yet, so we use hour + 1 for the current hour
	var current_hour = hour + 1
	var logs = []
	var display_hour = current_hour
	var hour_24 = GameConfig.STARTING_HOUR + display_hour
	if hour_24 >= 24:
		hour_24 -= 24
	var period = "pm" if hour_24 < 12 else "am"
	var display_hour_12 = hour_24 if hour_24 <= 12 else hour_24 - 12
	if display_hour_12 == 0:
		display_hour_12 = 12
	var time_str = "%d%s" % [display_hour_12, period]
	logs.append("[color=yellow]-- Hour %d (%s) --[/color]" % [display_hour, time_str])
	
	# Generate clients for this hour and store in queue
	var clients = _generate_clients_for_hour(current_hour)
	pending_client_queue = clients.duplicate()
	
	# Process first client from queue (if any)
	if pending_client_queue.size() > 0:
		var client_result = process_next_client_entry()
		logs.append_array(client_result.get("log_lines", []))
	else:
		# No clients this hour
		if tables.size() == 0:
			hour += 1
			logs.append("[i]No clients this hour.[/i]")
			
			# End of night check
			if hour >= GameConfig.HOURS_PER_NIGHT:
				logs.append_array(_calculate_night_summary())
			
			return {"log_lines": logs, "choices": [], "phrasebook_updates": []}
	
	# Handle empty table list after client entry
	if tables.size() == 0 and pending_table_assignments.is_empty():
		hour += 1
		logs.append("[i]No tables to serve this hour.[/i]")
		
		# End of night check
		if hour >= GameConfig.HOURS_PER_NIGHT:
			logs.append_array(_calculate_night_summary())
		
		return {"log_lines": logs, "choices": [], "phrasebook_updates": []}
	
	# Randomize table order for this hour
	# Exclude tables with pending assignments - they should be processed after assignment
	current_hour_tables = []
	var pending_table_labels = []
	for pending_table in pending_table_assignments:
		if typeof(pending_table) == TYPE_DICTIONARY:
			pending_table_labels.append(pending_table.get("label", ""))
	
	for table in tables:
		# Skip tables that are pending assignment
		if table.get("label", "") in pending_table_labels:
			continue
		# Include tables that are already assigned or unserved (but not pending)
		if table.get("active_wench", "") != "" or table.get("is_unserved", false):
			current_hour_tables.append(table)
	
	# Shuffle the array
	for i in range(current_hour_tables.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = current_hour_tables[i]
		current_hour_tables[i] = current_hour_tables[j]
		current_hour_tables[j] = temp
	
	# Initialize state
	current_table_index = 0
	hour_in_progress = true
	
	# If there are pending table assignments, wait for them to be assigned before processing
	if not pending_table_assignments.is_empty():
		# Don't start processing yet - wait for all pending assignments
		# Set hour_in_progress to true so we know we're waiting
		hour_in_progress = true
		current_table_index = -1  # No tables to process yet
		return {"log_lines": logs, "choices": [], "phrasebook_updates": []}
	
	# If there are no tables to process, return early
	if current_hour_tables.size() == 0:
		# No tables to process this hour
		return {"log_lines": logs, "choices": [], "phrasebook_updates": []}
	
	# Process first table
	var result = process_next_table()
	# Ensure result has all required keys with proper defaults
	if not result.has("log_lines"):
		result["log_lines"] = []
	if not result.has("choices"):
		result["choices"] = []
	if not result.has("phrasebook_updates"):
		result["phrasebook_updates"] = []
	
	# Prepend hour header and entry logs to existing logs
	var existing_logs = result.get("log_lines", [])
	if typeof(existing_logs) != TYPE_ARRAY:
		existing_logs = []
	# Combine hour header and entry logs with any existing logs from table processing
	result["log_lines"] = logs + existing_logs
	return result


func process_next_table() -> Dictionary:
	# Check if we have any tables to process
	if current_table_index < 0 or current_table_index >= current_hour_tables.size():
		# No more tables, hour is complete
		# Process table leaving AFTER all consumption updates
		var leaving_logs = _process_table_leaving()
		
		# Increment hours_occupied for remaining tables
		for table in tables:
			table["hours_occupied"] = table.get("hours_occupied", 0) + 1
		
		hour += 1
		hour_in_progress = false
		current_table_index = -1
		current_hour_tables.clear()
		
		var logs = []
		logs.append_array(leaving_logs)
		# End of night check (after HOURS_PER_NIGHT hours, 5pm to 1am)
		if hour >= GameConfig.HOURS_PER_NIGHT:
			logs.append_array(_calculate_night_summary())
		
		return {"log_lines": logs, "choices": [], "phrasebook_updates": []}
	
	# Safety check: ensure table still exists in main tables array
	var table = current_hour_tables[current_table_index]
	var table_exists = false
	for t in tables:
		if t == table or (t.has("label") and table.has("label") and t["label"] == table["label"]):
			table_exists = true
			# Update reference in case table object was replaced
			current_hour_tables[current_table_index] = t
			table = t
			break
	
	if not table_exists:
		# Table was removed (e.g., bounced), skip to next
		current_table_index += 1
		return process_next_table()
	var logs = []
	var choices = []
	var phrasebook_updates = []
	
	# Process this table: update stamina/availability/unserved for this table's wench
	_update_stamina_for_table(table)
	_check_wench_availability_for_table(table)
	_apply_unserved_penalties_for_table(table)
	
	# Update table rowdiness and consumption
	_update_table_rowdiness_for_table(table)
	
	# Generate phrasebook update for this table
	var table_phrasebook = _generate_phrasebook_update_for_table(table)
	if table_phrasebook.size() > 0:
		phrasebook_updates.append(table_phrasebook)
	
	# Roll event for this table
	var e = _roll_event_for_table(table)
	if e != "":  # Only resolve if an event occurred
		_resolve_event(table, e)
	
	# Check for fistfight (rowdiness >= ROWDINESS_FISTFIGHT) - must happen before intervention checks
	if table["rowdiness"] >= GameConfig.ROWDINESS_FISTFIGHT:
		phrasebook_updates.append({
			"table": table,
			"text": "[color=red]A fistfight breaks out at %s![/color]" % table["label"]
		})
		choices.append({
			"id": "fistfight_acknowledge_%s" % table["label"],
			"text": "Acknowledge (Table bounced)"
		})
		pending_choices = choices
	
	# Add rowdiness alerts (only for tables not at ROWDINESS_FISTFIGHT+)
	if table["rowdiness"] >= GameConfig.ROWDINESS_DANGEROUS and table["rowdiness"] < GameConfig.ROWDINESS_FISTFIGHT:
		phrasebook_updates.append({
			"table": table,
			"text": "[color=red]%s is getting dangerously rowdy![/color]" % table["label"]
		})
		choices.append({
			"id": "intervene_free_round_%s" % table["label"],
			"text": "Free round on the house"
		})
		choices.append({
			"id": "intervene_bouncer_%s" % table["label"],
			"text": "Bouncer call (step in personally)"
		})
		choices.append({
			"id": "intervene_ignore_%s" % table["label"],
			"text": "Ignore"
		})
		pending_choices = choices
	
	# Move to next table
	current_table_index += 1
	
	return {"log_lines": logs, "choices": choices, "phrasebook_updates": phrasebook_updates}


func apply_choice(choice_id: String) -> Dictionary:
	var logs = []

	if choice_id.begins_with("fistfight_acknowledge_"):
		var table_name = choice_id.replace("fistfight_acknowledge_", "")
		for i in range(tables.size() - 1, -1, -1):
			var table = tables[i]
			if table["label"] == table_name:
				var bounce_result = _bounce_table(table)
				logs.append("[b]A fistfight breaks out at %s![/b]" % table_name)
				logs.append("The bouncers throw them out. %s" % bounce_result["log_message"])
				tables.remove_at(i)
				# Also remove from current_hour_tables if it's there
				for j in range(current_hour_tables.size() - 1, -1, -1):
					if current_hour_tables[j]["label"] == table_name:
						current_hour_tables.remove_at(j)
						# Adjust index if we removed a table before the current position
						if j < current_table_index:
							current_table_index -= 1
						break
				break

	elif choice_id.begins_with("intervene_free_round_"):
		var table_name = choice_id.replace("intervene_free_round_", "")
		for table in tables:
			if table["label"] == table_name:
				# Calculate one hour's consumption (same formula as _consume_liquor_for_table)
				var group_size = table.get("group_size", 1)
				var social_status = table.get("social_status", "poor")
				var base_rate = GameConfig.SOCIAL_STATUS_BASE_DRAIN.get(social_status, 1.0)
				var pints_per_hour = int(ceil(group_size * base_rate))  # At least 1 pint per hour for the group
				var liquor_pref = table.get("liquor_preference", "cheap ale")
				var key := _liquor_key_from_preference(liquor_pref)
				
				# Deduct another hour's worth of stock (no gold cost - it's free)
				var actual_consumption = 0
				if stock.has(key) and stock[key] > 0:
					actual_consumption = min(pints_per_hour, stock[key])
					stock[key] -= actual_consumption
					stock[key] = max(stock[key], 0)
					liquor_stock_changed.emit(stock)
					
					# Update consumption counter (free round still counts as consumption for tracking)
					# This affects rowdiness/drunkenness calculations
					var current_consumption = table.get("consumption", 0)
					table["consumption"] = current_consumption + actual_consumption
					
					# Check if we ran out
					if stock[key] == 0:
						# Out of stock - customers are unhappy
						table["satisfaction"] += GameConfig.OUT_OF_STOCK_SATISFACTION_PENALTY
						table["rowdiness"] += GameConfig.OUT_OF_STOCK_ROWDINESS_PENALTY
				else:
					# Out of stock - customers are unhappy
					table["satisfaction"] += GameConfig.COMPLETELY_OUT_OF_STOCK_SATISFACTION_PENALTY
					table["rowdiness"] += GameConfig.COMPLETELY_OUT_OF_STOCK_ROWDINESS_PENALTY
				
				# Apply free round effects
				table["satisfaction"] += GameConfig.FREE_ROUND_SATISFACTION_BONUS
				table["rowdiness"] += GameConfig.FREE_ROUND_ROWDINESS_REDUCTION
				table["rowdiness"] = max(table["rowdiness"], 0.0)
				_update_table_event_chance(table)
				
				logs.append("[b]You offer a free round at %s.[/b]" % table_name)
				logs.append("The customers cheer! Satisfaction increases, and the rowdiness subsides.")
				break

	elif choice_id.begins_with("intervene_bouncer_"):
		var table_name = choice_id.replace("intervene_bouncer_", "")
		for table in tables:
			if table["label"] == table_name:
				# Apply effects
				table["satisfaction"] += GameConfig.BOUNCER_SATISFACTION_PENALTY
				table["rowdiness"] += GameConfig.BOUNCER_ROWDINESS_REDUCTION
				table["rowdiness"] = max(table["rowdiness"], 0.0)
				_update_table_event_chance(table)
				
				logs.append("[b]You step in personally at %s.[/b]" % table_name)
				logs.append("The customers quiet down, but they're not happy about being scolded.")
				break

	elif choice_id.begins_with("intervene_ignore_"):
		var table_name = choice_id.replace("intervene_ignore_", "")
		logs.append("[b]You decide to ignore the rowdiness at %s.[/b]" % table_name)
		logs.append("Nothing happens.")

	pending_choices.clear()
	
	# Auto-continue to next table if hour is in progress
	if hour_in_progress:
		var next_result = process_next_table()
		# Merge logs from choice with next table result
		next_result["log_lines"] = logs + next_result.get("log_lines", [])
		return next_result
	
	# No more tables, return just the choice logs
	return {"log_lines": logs, "choices": [], "phrasebook_updates": []}


func has_pending_choices() -> bool:
	return pending_choices.size() > 0


# --- HELPER FUNCTIONS ----------------------------------------------------

func _get_wench_mood(wench, _table: Dictionary) -> String:
	# Allow null wench - handle it gracefully
	if wench == null or typeof(wench) != TYPE_DICTIONARY:
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
	var template = phrasebook_templates[randi() % phrasebook_templates.size()]
	
	# Get wench for this table
	var wench = _wench_for_table(table)
	var wench_name = table.get("active_wench", "No one")
	if wench == null:
		wench_name = "No one"
	else:
		wench_name = wench.get("name", "No one")
	
	# Fill placeholders
	var text = template
	text = text.replace("{table}", table.get("label", "Unknown Table"))
	text = text.replace("{amount}", str(table.get("hourly_consumption", 0)))
	text = text.replace("{liquor}", _colorize_liquor(table.get("liquor_preference", "cheap ale")))
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


func _get_liquor_color(liquor_name: String) -> String:
	# Map each liquor type to a distinct color
	match liquor_name.to_lower():
		"cheap ale":
			return "tan"  # Light brown for common ale
		"cheap wine":
			return "pink"  # Light red/pink for wine
		"strong ale":
			return "orange"  # Amber/orange for stronger ale
		"mead":
			return "gold"  # Golden for honey-based mead
		"good wine":
			return "purple"  # Deep purple for premium wine
		_:
			return "white"  # Fallback color


func _colorize_liquor(liquor_name: String) -> String:
	var color = _get_liquor_color(liquor_name)
	return "[color=%s]%s[/color]" % [color, liquor_name]


func _get_time_string() -> String:
	# Service runs from 5pm (hour 1) to 3am (hour HOURS_PER_NIGHT)
	var hour_24 = GameConfig.STARTING_HOUR + hour
	if hour_24 >= 24:
		hour_24 -= 24
	var period = "pm" if hour_24 < 12 else "am"
	var display_hour = hour_24 if hour_24 <= 12 else hour_24 - 12
	if display_hour == 0:
		display_hour = 12
	return "%d%s" % [display_hour, period]


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
	return GameConfig.AVAILABLE_RACES[randi() % GameConfig.AVAILABLE_RACES.size()]


func _random_group_size() -> int:
	# Weighted towards smaller groups (1-6 people)
	var roll = randf()
	for size in GameConfig.GROUP_SIZE_DISTRIBUTION.keys():
		if roll < GameConfig.GROUP_SIZE_DISTRIBUTION[size]:
			return size
	return 6  # Fallback to max size


func _weighted_random(weights: Dictionary) -> String:
	var total = 0
	for key in weights:
		total += weights[key]
	
	var roll = randi() % total
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
		table["event_chance"] = float(table["rowdiness"]) / GameConfig.EVENT_CHANCE_DIVISOR
		
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

func _update_stamina_for_table(table: Dictionary) -> void:
	# Update stamina for the wench serving this table
	var wench_name = table.get("active_wench", "")
	if wench_name == "":
		return
	
	var w = null
	for wench in wenches:
		if wench.get("name", "") == wench_name:
			w = wench
			break
	
	if w == null:
		return
	
	# Calculate number of tables this wench is actively serving
	var active_table_count = 0
	for t in tables:
		if t.get("active_wench", "") == wench_name:
			active_table_count += 1
	
	# Base stamina drain + overwork penalty per extra table
	var stamina_drain = GameConfig.BASE_STAMINA_DRAIN
	if active_table_count > 1:
		stamina_drain += (active_table_count - 1) * GameConfig.OVERWORK_STAMINA_DRAIN_PER_TABLE
	
	w["stamina"] -= stamina_drain
	# No logging - information will come through phrasebook updates


func _update_table_rowdiness_for_table(table: Dictionary) -> void:
	# Update rowdiness for a single table based on:
	# 1. Race modifier (orcs rowdiest, then dwarves, etc.)
	# 2. Drunkenness (consumption over time)
	# 3. Group size (0.3 per person as rate modifier)
	
	# Ensure rowdiness is initialized
	if not table.has("rowdiness"):
		table["rowdiness"] = 0.0
	
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
	if stock.has(key) and stock[key] > 0:
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
		if stock[key] == 0:
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
	if randf() > event_chance:
		return ""  # No event this tick

	var weights = _event_table_for_group(table.get("group", ""))

	var total = 0
	for evt in weights:
		total += evt["weight"]

	var roll = randi() % total
	var sum = 0
	for evt in weights:
		sum += evt["weight"]
		if roll < sum:
			return evt["id"]
	return weights[0]["id"]


func _resolve_event(table: Dictionary, event_id: String) -> void:
	# Events still happen and affect game state, but no logging
	# Information will come through phrasebook updates
	
	var w = _wench_for_table(table)
	if w == null:
		return

	match event_id:
		"request_refill":
			_event_check(w, table, GameConfig.EVENT_DIFFICULTY_REQUEST_REFILL, "quick service", "delayed service")

		"flirt_minor":
			_event_check(w, table, GameConfig.EVENT_DIFFICULTY_FLIRT_MINOR, "graceful deflection", "awkward moment")

		"spill_drink":
			_event_check(w, table, GameConfig.EVENT_DIFFICULTY_SPILL_DRINK, "smooth recovery", "big mess")

		"rowdy_noise":
			table["rowdiness"] += GameConfig.ROWDY_NOISE_ROWDINESS_PENALTY
			_update_table_event_chance(table)



func _event_check(w: Dictionary, table: Dictionary, difficulty: int, success_msg: String, fail_msg: String) -> void:
	# Events still affect game state, but no logging
	# Information will come through phrasebook updates
	
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
	
	var roll = w["charm"] + randi() % 5 - fatigue_penalty + race_modifier
	var adjusted_difficulty = difficulty + overwork_difficulty

	if roll >= adjusted_difficulty:
		# Apply service efficiency penalty to satisfaction gains
		var satisfaction_gain = int(GameConfig.EVENT_SUCCESS_BASE_SATISFACTION * efficiency_multiplier)
		table["satisfaction"] += satisfaction_gain
	else:
		table["satisfaction"] += GameConfig.EVENT_FAIL_SATISFACTION_PENALTY
		table["rowdiness"] += GameConfig.EVENT_FAIL_ROWDINESS_PENALTY
		_update_table_event_chance(table)


func _wench_for_table(table: Dictionary):
	if typeof(table) != TYPE_DICTIONARY:
		return null
	
	var active_wench_name = table.get("active_wench", "")
	if active_wench_name == "":
		return null

	for w in wenches:
		if w["name"] == active_wench_name:
			return w
	return null


func _promote_backup_wench(table: Dictionary) -> bool:
	# Check if table has backup wenches
	var backup_wenches = table.get("backup_wenches", [])
	if backup_wenches.size() == 0:
		return false
	
	# Find first available backup wench (state == "serving")
	for backup_name in backup_wenches:
		for w in wenches:
			if w["name"] == backup_name and w.get("current_state", "serving") == "serving":
				# Promote this backup to active
				table["active_wench"] = backup_name
				table["is_unserved"] = false
				return true
	
	# No backup available
	return false


func _check_wench_availability_for_table(table: Dictionary) -> void:
	# Check if the wench assigned to this table is available
	var wench_name = table.get("active_wench", "")
	if wench_name == "":
		return
	
	var w = null
	for wench in wenches:
		if wench.get("name", "") == wench_name:
			w = wench
			break
	
	if w == null:
		return
	
	# If wench is not serving, try to promote backup or mark as unserved
	if w.get("current_state", "serving") != "serving":
		# Try to promote a backup
		if not _promote_backup_wench(table):
			# No backup available, mark as unserved
			table["is_unserved"] = true
			table["active_wench"] = ""
			# No logging - information will come through phrasebook updates


func _apply_unserved_penalties_for_table(table: Dictionary) -> void:
	# For unserved tables, apply penalties per hour
	if table.get("is_unserved", false):
		table["rowdiness"] += GameConfig.UNSERVED_ROWDINESS_PENALTY
		table["satisfaction"] += GameConfig.UNSERVED_SATISFACTION_PENALTY
		# Update event chance calculation (clamp rowdiness)
		_update_table_event_chance(table)
		# Apply multiplier after recalculation
		var current_chance = table.get("event_chance", 0.0)
		table["event_chance"] = current_chance * GameConfig.UNSERVED_EVENT_CHANCE_MULTIPLIER
		# No logging - information will come through phrasebook updates


func _event_table_for_group(group: String) -> Array:
	if GameConfig.GROUP_EVENT_WEIGHTS.has(group):
		return GameConfig.GROUP_EVENT_WEIGHTS[group]
	return GameConfig.DEFAULT_EVENT_WEIGHTS


# Helper function to check if a table is truly available
func _is_table_available(table: Dictionary, assigned_tables: Array) -> bool:
	# Check if table is occupied
	if table.get("hours_occupied", 0) > 0:
		return false
	# Check if table already has a wench assigned
	if table.get("active_wench", "") != "":
		return false
	# Check if table label is in assigned_tables (already claimed this iteration)
	var table_label = table.get("label", "")
	if table_label in assigned_tables:
		return false
	# Check if table is pending assignment
	for pending in pending_table_assignments:
		if typeof(pending) == TYPE_DICTIONARY:
			if pending.get("label", "") == table_label:
				return false
	return true


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


# Process a single client entry attempt
# Returns Dictionary with "log" (String) and "success" (bool)
func _attempt_single_client_entry(client: Dictionary) -> Dictionary:
	# Track which tables have been assigned in this iteration to prevent duplicates
	# Get all currently assigned/pending tables
	var assigned_tables = []
	for table in tables:
		if table.get("hours_occupied", 0) > 0 or table.get("active_wench", "") != "":
			assigned_tables.append(table.get("label", ""))
	for pending in pending_table_assignments:
		if typeof(pending) == TYPE_DICTIONARY:
			assigned_tables.append(pending.get("label", ""))
	
	# Collect all available tables
	var available_tables = []
	for table in tables:
		if _is_table_available(table, assigned_tables):
			available_tables.append(table)
	
	# Shuffle available tables for random selection
	if available_tables.size() > 0:
		# Shuffle the array
		for i in range(available_tables.size() - 1, 0, -1):
			var j = randi() % (i + 1)
			var temp = available_tables[i]
			available_tables[i] = available_tables[j]
			available_tables[j] = temp
		
		# Select first table from shuffled array (random selection)
		var empty_table = available_tables[0]
		var table_label = empty_table.get("label", "")
		
		# 50% chance to enter
		if randf() < GameConfig.CLIENT_ENTRY_CHANCE:
			# Update the empty table with new client data
			empty_table["social_status"] = client["social_status"]
			empty_table["race"] = client["race"]
			empty_table["group_size"] = client["group_size"]
			empty_table["liquor_preference"] = _get_liquor_for_status(client["social_status"])
			empty_table["description"] = "A %s group of %s %s" % [
				_get_size_description(client["group_size"]),
				client["social_status"],
				client["race"] + "s"
			]
			empty_table["group"] = empty_table["description"]  # Keep for backward compatibility
			
			# Recalculate resource drain rate for new group
			var base_rate = GameConfig.SOCIAL_STATUS_BASE_DRAIN.get(client["social_status"], 1.0)
			var size_modifier = 1.0
			if client["group_size"] > 2:
				size_modifier = 1.0 + (client["group_size"] - 2) * GameConfig.GROUP_SIZE_DRAIN_MODIFIER
			empty_table["resource_drain_rate"] = base_rate * size_modifier
			
			# Reset table state for new customers
			empty_table["rowdiness"] = 0
			empty_table["consumption"] = 0
			empty_table["satisfaction"] = 0
			empty_table["event_chance"] = 0.0
			# Set hours_occupied to 1 to mark it as occupied (will be incremented at end of hour)
			empty_table["hours_occupied"] = 1
			
			# Add to pending assignments for manual wench selection
			pending_table_assignments.append(empty_table)
			
			var log_msg = "%s enters and sits at %s. [color=yellow]Select a wench to assign.[/color]" % [empty_table.get("description", "A group"), table_label]
			return {"log": log_msg, "success": true}
		else:
			# Entry chance failed
			return {"log": "", "success": false}
	
	# No empty table available - check if we can create a new one
	if tables.size() >= GameConfig.NUM_TABLES:
		# No tables available
		return {"log": "", "success": false}
	
	# 50% chance to enter
	if randf() < GameConfig.CLIENT_ENTRY_CHANCE:
		# Client enters - create a new table
		var next_table_id = tables.size() + 1
		var label = "Table %d" % next_table_id
		var table = _make_table(
			next_table_id,
			label,
			client["social_status"],
			client["race"],
			client["group_size"]
		)
		
		# Add to pending assignments for manual wench selection
		pending_table_assignments.append(table)
		
		tables.append(table)
		var log_msg = "%s enters and sits at %s. [color=yellow]Select a wench to assign.[/color]" % [table.get("description", "A group"), label]
		return {"log": log_msg, "success": true}
	
	return {"log": "", "success": false}


# Process the next client from the queue
func process_next_client_entry() -> Dictionary:
	var logs = []
	
	if pending_client_queue.is_empty():
		# No more clients to process
		return {"log_lines": logs, "choices": [], "phrasebook_updates": []}
	
	# Get next client from queue
	var client = pending_client_queue[0]
	pending_client_queue.remove_at(0)
	
	# Attempt entry for this client
	var result = _attempt_single_client_entry(client)
	
	if result["success"]:
		# Client entered successfully
		logs.append(result["log"])
	
	# Return result (even if entry failed, we still processed the client)
	return {"log_lines": logs, "choices": [], "phrasebook_updates": []}


func _assign_wench_to_new_table(table: Dictionary, wench_name: String = "") -> void:
	# Assign a wench to a newly created table
	# If wench_name is provided, use that wench; otherwise use round-robin load balancing
	
	var best_wench = null
	
	if wench_name != "":
		# Find the specified wench
		for w in wenches:
			if w.get("name", "") == wench_name:
				# Check if wench is available
				if w.get("current_state", "serving") == "serving":
					best_wench = w
				break
	else:
		# Auto-assign using round-robin (load balancing)
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
		var min_tables = 999999
		for w in available_wenches:
			var count = wench_table_counts.get(w["name"], 0)
			if count < min_tables:
				min_tables = count
				best_wench = w
	
	if best_wench != null:
		table["active_wench"] = best_wench["name"]
		table["is_unserved"] = false
		# Add to wench's assigned tables
		if not best_wench["assigned_tables"].has(table["label"]):
			best_wench["assigned_tables"].append(table["label"])
		
		# Set backup wenches (all other available wenches)
		var available_wenches = []
		for w in wenches:
			if w.get("current_state", "serving") == "serving" and w["name"] != best_wench["name"]:
				available_wenches.append(w["name"])
		table["backup_wenches"] = available_wenches
	else:
		table["is_unserved"] = true

# Assign a wench to the next pending table (called from UI when player selects a wench)
func assign_wench_to_pending_table(wench_name: String) -> Dictionary:
	var logs = []
	
	if pending_table_assignments.is_empty():
		# No pending tables, return empty result
		return {"log_lines": logs, "choices": [], "phrasebook_updates": []}
	
	# Get the first pending table (process one at a time)
	var pending_table = pending_table_assignments[0]
	var table_label = pending_table.get("label", "Unknown table")
	var table = null
	
	# Find the actual table in the tables array to ensure we have the correct reference
	for t in tables:
		if t.get("label", "") == table_label:
			table = t
			break
	
	if table == null:
		# Table not found, something went wrong - remove from pending and try next
		push_error("Table %s not found in tables array" % table_label)
		pending_table_assignments.remove_at(0)
		# If there are more pending tables, return a message to continue
		if not pending_table_assignments.is_empty():
			return {"log_lines": ["[color=red]Error assigning table. Please try again.[/color]"], "choices": [], "phrasebook_updates": []}
		return {"log_lines": logs, "choices": [], "phrasebook_updates": []}
	
	# Assign the wench
	_assign_wench_to_new_table(table, wench_name)
	
	# Remove this table from pending assignments
	pending_table_assignments.remove_at(0)
	
	logs.append("[color=green]%s assigned to %s.[/color]" % [wench_name, table.get("label", "Unknown table")])
	
	# If there are more pending tables, don't process yet - wait for next assignment
	if not pending_table_assignments.is_empty():
		# More tables need assignment - return early without processing
		return {"log_lines": logs, "choices": [], "phrasebook_updates": []}
	
	# All pending tables are assigned - check if there are more clients in queue
	if not pending_client_queue.is_empty():
		# Process next client from queue
		var client_result = process_next_client_entry()
		# Merge logs
		client_result["log_lines"] = logs + client_result.get("log_lines", [])
		return client_result
	
	# All pending tables are assigned and no more clients in queue - now we can start processing
	# If hour is in progress, rebuild current_hour_tables to include all assigned tables
	if hour_in_progress and pending_client_queue.is_empty():
		# Rebuild current_hour_tables to include all assigned tables (including newly assigned ones)
		# This ensures we process all tables in the correct order
		current_hour_tables.clear()
		for t in tables:
			# Include all tables that have a wench assigned (or are unserved)
			if t.get("active_wench", "") != "" or t.get("is_unserved", false):
				current_hour_tables.append(t)
		
		# Shuffle the array for random processing order
		for i in range(current_hour_tables.size() - 1, 0, -1):
			var j = randi() % (i + 1)
			var temp = current_hour_tables[i]
			current_hour_tables[i] = current_hour_tables[j]
			current_hour_tables[j] = temp
		
		# If we have tables to process, start processing
		if current_hour_tables.size() > 0:
			# Start from the beginning
			current_table_index = 0
			
			# Process the first table
			var process_result = process_next_table()
			# Merge logs
			process_result["log_lines"] = logs + process_result.get("log_lines", [])
			return process_result
	
	return {"log_lines": logs, "choices": [], "phrasebook_updates": []}

# Check if there's a pending table assignment
func has_pending_table_assignment() -> bool:
	return not pending_table_assignments.is_empty()
	
# Get the next pending table label (for UI display)
func get_next_pending_table_label() -> String:
	if pending_table_assignments.is_empty():
		return ""
	var next_table = pending_table_assignments[0]
	if typeof(next_table) == TYPE_DICTIONARY:
		return next_table.get("label", "")
	return ""


func _process_table_leaving() -> Array:
	# Process table leaving after consumption updates
	# Returns array of log messages
	var logs = []
	var tables_to_remove = []
	
	# Check if this is the last hour (hour 8) - last call, all tables leave
	var is_last_hour = (hour + 1) >= GameConfig.HOURS_PER_NIGHT
	
	for table in tables:
		var should_leave = false
		
		if is_last_hour:
			# Last call - all tables leave
			should_leave = true
		else:
			# Calculate leave chance based on hours occupied
			var hours_occupied = table.get("hours_occupied", 0)
			var leave_chance = GameConfig.LEAVE_CHANCE_BASE
			if hours_occupied > 0:
				leave_chance = GameConfig.LEAVE_CHANCE_BASE + (hours_occupied - 1) * GameConfig.LEAVE_CHANCE_INCREMENT
			leave_chance = min(leave_chance, 1.0)  # Cap at 100%
			
			# Roll to leave
			if randf() < leave_chance:
				should_leave = true
		
		if should_leave:
			# Calculate tips and pay to waitress
			var tips = _calculate_table_tips(table)
			var wench_name = table.get("active_wench", "")
			
			if wench_name != "":
				# Find wench and add tips
				for w in wenches:
					if w["name"] == wench_name:
						w["tips_earned"] += tips
						logs.append("%s leaves, paying %d gold in tips to %s." % [table.get("label", "Unknown table"), tips, wench_name])
						break
			else:
				logs.append("%s leaves without paying tips (no waitress assigned)." % table.get("label", "Unknown table"))
			
			tables_to_remove.append(table)
	
	# Remove tables that are leaving
	for table in tables_to_remove:
		var index = tables.find(table)
		if index >= 0:
			tables.remove_at(index)
			# Also remove from current_hour_tables if present
			for i in range(current_hour_tables.size() - 1, -1, -1):
				if current_hour_tables[i] == table or (current_hour_tables[i].has("label") and table.has("label") and current_hour_tables[i]["label"] == table["label"]):
					current_hour_tables.remove_at(i)
					# Adjust index if we removed a table before current position
					if i < current_table_index:
						current_table_index -= 1
	
	return logs


func _append_table_overview(logs: Array) -> void:
	logs.append("[i]Tonight's floor plan:[/i]")
	for table in tables:
		if typeof(table) != TYPE_DICTIONARY:
			logs.append("- [unknown table] (data missing)")
			continue

		var active_wench_name = table.get("active_wench", "")
		var server = "No one"
		if active_wench_name != "":
			server = active_wench_name
		elif table.get("is_unserved", false):
			server = "[UNSERVED]"

		# Use new description format if available, otherwise fall back to old format
		var description = table.get("description", "")
		if description == "":
			description = table.get("group", "Unknown guests")
		
		var backup_wenches = table.get("backup_wenches", [])
		var backup_str = ""
		if backup_wenches.size() > 0:
			backup_str = " (backups: %s)" % ", ".join(backup_wenches)
		
		logs.append("- %s: %s (served by %s%s)" %
			[table.get("label", "Unknown table"), description, server, backup_str])
		
		# Show additional table info for debugging/visibility
		if table.has("liquor_preference"):
			var drain_rate = table.get("resource_drain_rate", 1.0)
			var group_size = table.get("group_size", 1)
			var pints_per_hour = int(ceil(group_size * drain_rate))
			var colorized_liquor = _colorize_liquor(table["liquor_preference"])
			logs.append("  [i]Prefers: %s | Event chance: %.1f%% | Consumption: ~%d pints/hour[/i]" %
				[colorized_liquor, table.get("event_chance", 0.0) * 100, pints_per_hour])


func _calculate_night_summary() -> Array:
	var logs = []
	logs.append("")
	logs.append("[b]--- End of Night Summary ---[/b]")
	
	# Calculate average satisfaction (from all tables that existed during the night)
	# Note: tables array may be empty if all left, but we still show stats if we had tables
	var total_satisfaction = 0
	var table_count = 0
	for table in tables:
		if typeof(table) == TYPE_DICTIONARY:
			total_satisfaction += table.get("satisfaction", 0)
			table_count += 1
	
	var avg_satisfaction = 0.0
	if table_count > 0:
		avg_satisfaction = float(total_satisfaction) / float(table_count)
		logs.append("Average satisfaction: %.1f" % avg_satisfaction)
	else:
		logs.append("Average satisfaction: N/A (no tables served)")
	
	# Process any remaining tables (they should have left already, but just in case)
	for table in tables:
		if typeof(table) != TYPE_DICTIONARY:
			continue
		
		var tips = _calculate_table_tips(table)
		var wench_name = table.get("active_wench", "")
		
		if wench_name != "":
			for w in wenches:
				if w["name"] == wench_name:
					w["tips_earned"] += tips
					break
	
	# Show wench earnings
	logs.append("")
	logs.append("[b]Wench Earnings:[/b]")
	var total_tips = 0
	for w in wenches:
		if typeof(w) == TYPE_DICTIONARY:
			var tips = w.get("tips_earned", 0)
			total_tips += tips
			logs.append("%s: %d gold in tips" % [w.get("name", "Unknown"), tips])
	
	logs.append("Total tips earned: %d" % total_tips)
	logs.append("Total gold from sales: %d" % gold)
	logs.append("Total revenue: %d" % (gold + total_tips))
	
	# Find most tired wench (lowest current stamina)
	var most_tired_wench = null
	var lowest_stamina = 999999
	for w in wenches:
		if typeof(w) == TYPE_DICTIONARY:
			var stamina = w.get("stamina", 0)
			if stamina < lowest_stamina:
				lowest_stamina = stamina
				most_tired_wench = w
	
	if most_tired_wench != null:
		logs.append("Most tired wench: %s (stamina: %d)" % [most_tired_wench.get("name", "Unknown"), lowest_stamina])
	else:
		logs.append("Most tired wench: None")
	
	# Find rowdiest table (highest rowdiness) - only if tables still exist
	var rowdiest_table = null
	var highest_rowdiness = -1.0
	for table in tables:
		if typeof(table) == TYPE_DICTIONARY:
			var rowdiness = table.get("rowdiness", 0.0)
			if rowdiness > highest_rowdiness:
				highest_rowdiness = rowdiness
				rowdiest_table = table
	
	if rowdiest_table != null:
		logs.append("Rowdiest table: %s (rowdiness: %.1f)" % [rowdiest_table.get("label", "Unknown"), highest_rowdiness])
	else:
		logs.append("Rowdiest table: None")
	
	return logs


func _calculate_table_tips(table: Dictionary) -> int:
	# Calculate tips for a table when they leave
	# Formula ensures waitress gets max 30% of table's consumption value
	# Base tip: 10% of consumption value
	# Satisfaction bonus: up to +20% (max 30% total)
	# Note: Tips are now paid to waitresses, not added to gold total
	var consumption = table.get("consumption", 0)  # in pints
	var satisfaction = table.get("satisfaction", 0)
	var liquor_pref = table.get("liquor_preference", "cheap ale")
	var base_price = GameConfig.LIQUOR_PRICES.get(liquor_pref, 1)
	
	# Calculate total consumption value
	var consumption_value = consumption * base_price
	
	# Base tip percentage (10% of consumption value)
	var base_tip_percent = 0.10
	
	# Satisfaction bonus: scales from 0% to 20% based on satisfaction
	# Satisfaction range: -10 to +10 (roughly), maps to 0% to 20% bonus
	# Clamp satisfaction to reasonable range for calculation
	var clamped_satisfaction = clamp(satisfaction, -10, 10)
	# Map -10 to 0% bonus, +10 to 20% bonus
	var satisfaction_bonus_percent = ((clamped_satisfaction + 10.0) / 20.0) * 0.20
	
	# Total tip percentage (base + bonus, capped at 30%)
	var total_tip_percent = min(base_tip_percent + satisfaction_bonus_percent, 0.30)
	
	# Calculate tips
	var tips = consumption_value * total_tip_percent
	return int(tips)


func _bounce_table(table: Dictionary) -> Dictionary:
	# Calculate lost tips using _calculate_table_tips
	# Note: Tips are never added to gold for bounced tables, so we don't subtract anything
	# The upfront payment was already collected, but tips are lost
	var lost_tips = _calculate_table_tips(table)
	
	return {
		"lost_tips": lost_tips,
		"log_message": "Lost %d gold in tips from %s." % [lost_tips, table.get("label", "Unknown Table")]
	}

# --- INITIALIZATION ------------------------------------------------------

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
		var colorized_name = _colorize_liquor(display_name)
		logs.append("%s: %d pints" % [colorized_name, stock[liquor_type]])
	logs.append("")


func _init_wenches():
	wenches.clear()
	wenches.append(_make_wench("Lysa", 7, 4, 3, [], "elf"))
	wenches.append(_make_wench("Brakka", 3, 5, 8, [], "human"))
	wenches.append(_make_wench("Mimi", 5, 8, 5, [], "tiefling"))


func _init_tables():
	tables.clear()
	# Generate random tables
	for i in range(GameConfig.NUM_TABLES):
		var table_id = i + 1
		var label = "Table %d" % table_id
		var social_status = _random_social_status()
		var race = _random_race()
		var group_size = _random_group_size()
		tables.append(_make_table(table_id, label, social_status, race, group_size))


func _assign_wenches_to_tables():
	# Find wenches by name
	var wench1 = null  # Lysa
	var wench2 = null  # Brakka
	var wench3 = null  # Mimi
	
	for w in wenches:
		if w["name"] == "Lysa":
			wench1 = w
		elif w["name"] == "Brakka":
			wench2 = w
		elif w["name"] == "Mimi":
			wench3 = w
	
	# Assign Tables 1-2 to Wench 1 (Lysa)
	if wench1 != null:
		wench1["assigned_tables"] = ["Table 1", "Table 2"]
		for table in tables:
			if table["label"] == "Table 1" or table["label"] == "Table 2":
				table["active_wench"] = wench1["name"]
				table["backup_wenches"] = [wench2["name"], wench3["name"]]
	
	# Assign Tables 3-4 to Wench 2 (Brakka)
	if wench2 != null:
		wench2["assigned_tables"] = ["Table 3", "Table 4"]
		for table in tables:
			if table["label"] == "Table 3" or table["label"] == "Table 4":
				table["active_wench"] = wench2["name"]
				table["backup_wenches"] = [wench1["name"], wench3["name"]]
	
	# Assign Tables 5-6 to Wench 3 (Mimi)
	if wench3 != null:
		wench3["assigned_tables"] = ["Table 5", "Table 6"]
		for table in tables:
			if table["label"] == "Table 5" or table["label"] == "Table 6":
				table["active_wench"] = wench3["name"]
				table["backup_wenches"] = [wench1["name"], wench2["name"]]


func _make_wench(name, charm, service, stamina, assigned_tables, race = "human"):
	return {
		"name": name,
		"charm": charm,
		"service": service,
		"stamina": stamina,
		"max_stamina": stamina,
		"assigned_tables": assigned_tables,
		"current_state": "serving",
		"traits": [],
		"race": race,
		"tips_earned": 0,  # Track tips earned by this wench
	}


func _make_table(id: int, label: String, social_status: String, race: String, group_size: int):
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
		"backup_wenches": [],
		"is_unserved": false,
		"hourly_consumption": 0,  # Track consumption for this hour (for phrasebook)
		"hours_occupied": 0,  # Track how many hours this table has been occupied
	}
