extends SceneTree
## Run with a graphics display to capture the real Godot viewport.
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var ui = load("res://CounterMain.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.sim.start_new_night(12)
	for slot in range(1, 5):
		var table: Dictionary = ui.sim._make_table(slot, "Table %d" % slot, "poor" if slot != 3 else "merchant", "human", slot + 1)
		table["active_wench"] = ["Lysa", "Brakka", "Mimi"][(slot - 1) % 3]
		table["is_unserved"] = false
		table["satisfaction"] = slot
		table["rowdiness"] = slot * 2.0
		ui.sim.tables.append(table)
	ui.sim._sync_assignments()
	ui._apply(ui.sim._begin_table_processing())
	ui.timer.stop()
	var order: Dictionary = ui.sim.pending_order
	for i in mini(3, order["quantity"]): ui._add_product(order["product"])
	ui._add_coin(5)
	ui._add_coin(2)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var target := "/tmp/wench-runtime/counter.png"
	root.get_texture().get_image().save_png(target)
	print("Captured: ", target)
	quit()
