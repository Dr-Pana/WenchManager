extends SceneTree
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func fixture(amount: int = 90) -> Simulation:
	var sim := Simulation.new()
	sim.counter_service_enabled = true
	sim.start_new_night(12)
	var table: Dictionary = sim._make_table(1, "Table 1", "poor", "human", 3)
	table["active_wench"] = "Brakka"
	table["is_unserved"] = false
	sim.tables.append(table)
	sim.stock["cheap_ale"] = amount
	sim._begin_table_processing()
	return sim

func settle(sim: Simulation) -> Dictionary:
	var o := sim.pending_order.duplicate(true)
	var quantity := mini(o["quantity"], sim.stock[o["stock_key"]])
	return sim.submit_counter_order(o["id"], {o["product"]: quantity}, o["tender"] - quantity * o["unit_price"])

func run() -> void:
	var sim := fixture()
	check(sim.phase == Simulation.Phase.AWAITING_ORDER and sim.hour_in_progress, "Order pauses the active hour")
	check(sim.stock["cheap_ale"] == 90 and sim.gold == 0, "Presenting order spends nothing")
	var o := sim.pending_order.duplicate(true)
	var snapshot := sim.stock.duplicate()
	check(not sim.submit_counter_order(o["id"], {"mead": 3}, 7)["accepted"], "Wrong items rejected")
	check(not sim.submit_counter_order(o["id"], {"cheap ale": -3}, 7)["accepted"], "Negative quantities rejected")
	check(not sim.submit_counter_order(o["id"], {"cheap ale": 3.0}, 7)["accepted"], "Noninteger quantities rejected")
	check(not sim.submit_counter_order(o["id"], {"cheap ale": 3}, 0)["accepted"], "Incorrect change rejected")
	check(sim.stock == snapshot and sim.gold == 0 and sim.receipts.is_empty(), "Invalid attempts have no economic effect")
	sim.advance_hour()
	sim.process_next_table()
	check(sim.pending_order == o and sim.hour == 0, "Hour and next-table inputs cannot bypass pending order")
	check(settle(sim)["accepted"], "Correct tray and change accepted")
	check(sim.gold == 3 and sim.stock["cheap_ale"] == 87 and sim.receipts.size() == 1, "Single settlement deducts stock and books net payment once")
	check(not sim.submit_counter_order(o["id"], {"cheap ale": 3}, 7)["accepted"] and sim.gold == 3, "Duplicate settlement rejected")
	sim.start_new_night(12)
	check(sim.pending_order.is_empty() and sim.receipts.is_empty(), "Restart clears order and receipts")
	check(not sim.submit_counter_order(o["id"], {"cheap ale": 3}, 7)["accepted"], "Prior-night order rejected")
	for amount in [0, 2, 3]:
		sim = fixture(amount)
		settle(sim)
		check(sim.gold == amount and sim.stock["cheap_ale"] == 0, "Short or exact stock settles only delivered items")
		var receipt: Dictionary = sim.receipts[0]
		check(receipt["tender"] - receipt["change"] == receipt["sale"], "Payment is conserved")
	sim = fixture()
	sim.submit_counter_order(sim.pending_order["id"], {}, 0, true)
	check(sim.gold == 0 and sim.stock["cheap_ale"] == 90 and sim.receipts[0]["skipped"], "Decline refunds all payment and spends no stock")
	for amount in [0, 2, 3]:
		sim = fixture(amount)
		sim.pending_order.clear()
		sim.phase = Simulation.Phase.AWAITING_CHOICE
		var table: Dictionary = sim.tables[0]
		table["rowdiness"] = 11.0
		sim.pending_choices = [sim._choice("free_round", "Free round", table)]
		var result := sim.apply_choice(sim.pending_choices[0]["id"])
		var expected: int = {0: -1, 2: 0, 3: 2}[amount]
		check(table["satisfaction"] == expected and str(result["log_lines"].back()).contains("Delivered"), "Free round reports actual effects including exact-stock fulfillment")
	# Ten full nights exercise arrival, assignment, orders, decisions, departures, recovery and closing.
	for seed_value in range(10):
		sim = Simulation.new()
		sim.counter_service_enabled = true
		sim.start_new_night(seed_value)
		var budget := 1000
		while sim.phase != Simulation.Phase.CLOSED and budget > 0:
			budget -= 1
			match sim.phase:
				Simulation.Phase.BETWEEN_HOURS: sim.advance_hour()
				Simulation.Phase.ADMITTING: sim.process_next_client_entry()
				Simulation.Phase.AWAITING_ASSIGNMENT:
					for w in sim.wenches:
						if w["current_state"] == "serving":
							sim.assign_wench_to_pending_table(w["name"], sim.pending_table_assignments[0]["visit_id"], sim.night_serial)
							break
				Simulation.Phase.AWAITING_ORDER: settle(sim)
				Simulation.Phase.PROCESSING: sim.process_next_table()
				Simulation.Phase.AWAITING_CHOICE: sim.apply_choice(sim.pending_choices.back()["id"])
		var sales := 0
		for receipt in sim.receipts: sales += receipt["sale"]
		check(budget > 0 and sim.hour == 8 and sim.tables.is_empty(), "Counter night reaches closing")
		check(sim.gold == sales, "Night sales match counter receipt ledger")
	# Exercise real scene controls and layout, not just simulation calls.
	var ui = load("res://CounterMain.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.timer.stop()
	check(ui.sim.counter_service_enabled and not ui.next_button.disabled, "Default scene enables counter service")
	ui.sim = fixture()
	ui._apply({})
	ui.timer.stop()
	await process_frame
	check(ui.serve_button.get_global_rect().end.y <= root.get_visible_rect().size.y, "Serve action stays in fixed footer")
	check(not ui.serve_button.disabled and ui.host_portrait.texture != null, "Pending order exposes server portrait and controls")
	ui.shelf_buttons[0].pressed.emit()
	ui.tray_art.item_removed.emit("cheap ale")
	check(ui.tray.get("cheap ale", 0) == 0 and ui.sim.stock["cheap_ale"] == 90, "Removing staged mug returns it without spending inventory")
	ui.shelf_buttons[0].pressed.emit()
	ui.shelf_buttons[0].pressed.emit()
	ui.shelf_buttons[0].pressed.emit()
	ui.coin_buttons[2].pressed.emit()
	ui.coin_buttons[1].pressed.emit()
	ui.serve_button.pressed.emit()
	ui.timer.stop()
	check(ui.sim.gold == 3 and ui.sim.receipts.size() == 1, "Shelf, coin and serve signals settle a real transaction")
	ui._start_night()
	check(ui.tray.is_empty() and ui.change_coins.is_empty() and ui.order_id.is_empty(), "Scene restart clears staged tray and payment")
	await process_frame
	check(ui.next_button.get_global_rect().end.y <= root.get_visible_rect().size.y, "Primary footer stays on screen")
	ui.queue_free()
	await process_frame
	print("Counter: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
