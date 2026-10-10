extends Control
## A scalable, clickable floor. Visual state is supplied by the controller.
signal table_selected(slot: int)
var tables: Array = []
var selected_slot := 1
var attention_slot := -1
var portraits: Dictionary = {}
var font: Font = ThemeDB.fallback_font
const GOLD := Color("ddb36b")
const MUTED := Color("b3a18a")

func _ready() -> void:
	custom_minimum_size = Vector2(540, 320)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)

func center_for(slot: int) -> Vector2:
	return Vector2(size.x * (0.19 + ((slot - 1) % 3) * 0.31), size.y * (0.34 + int((slot - 1) / 3) * 0.43))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for slot in range(1, 7):
			if Rect2(center_for(slot) - Vector2(82, 67), Vector2(164, 134)).has_point(event.position):
				table_selected.emit(slot)
				accept_event()

func word(at: Vector2, text: String, color: Color = MUTED, font_size: int = 14) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("211c1b"))
	for y in range(0, int(size.y), 24):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("322724"), 1)
		for x in range((y % 48) * 4, int(size.x), 160):
			draw_line(Vector2(x, y), Vector2(x, y + 24), Color("161515"), 1)
	# Tall windows and lamplight establish the room without hiding gameplay.
	for x in [size.x * 0.25, size.x * 0.75]:
		draw_style_box(_box(Color("39322b")), Rect2(x - 48, 5, 96, 40))
		draw_rect(Rect2(x - 39, 10, 78, 28), Color("253941"))
		draw_line(Vector2(x, 10), Vector2(x, 38), GOLD.darkened(0.55), 3)
		draw_circle(Vector2(x, 49), 5, GOLD)
	word(Vector2(14, 25), "THE FLOOR", GOLD, 13)
	for slot in range(1, 7):
		var c := center_for(slot)
		var table: Dictionary = {}
		for t in tables:
			if t["id"] == slot:
				table = t
		var active := not table.is_empty()
		var guests: int = table.get("group_size", 0)
		for seat in range(6):
			var angle := TAU * seat / 6.0
			var pos := c + Vector2(cos(angle) * 73, sin(angle) * 43)
			draw_circle(pos + Vector2(0, 4), 12, Color("100f10"))
			draw_circle(pos, 10, Color("5c4740"))
			if seat < guests:
				draw_circle(pos, 7, Color("b9aa87"))
		var rect := Rect2(c - Vector2(60, 34), Vector2(120, 68))
		draw_style_box(_box(Color("674936") if active else Color("3a302a")), rect)
		if slot == selected_slot or slot == attention_slot:
			var outline := _box(Color.TRANSPARENT)
			outline.border_color = Color("e99764") if slot == attention_slot else GOLD
			outline.set_border_width_all(2)
			draw_style_box(outline, rect.grow(4))
		word(c + Vector2(-49, -12), "%02d" % slot, GOLD, 17)
		if active:
			var server: String = table.get("active_wench", "")
			if portraits.has(server):
				draw_texture_rect(portraits[server], Rect2(c + Vector2(17, -27), Vector2(36, 48)), false)
			word(c + Vector2(-49, 8), "%d guests" % guests, Color("eee0c9"), 13)
			word(c + Vector2(-49, 25), "%+d mood" % table["satisfaction"], Color("90b8a0") if table["satisfaction"] >= 0 else Color("ef997e"), 12)
			var level := clampf(float(table["rowdiness"]) / 15.0, 0, 1)
			draw_rect(Rect2(c + Vector2(-49, 49), Vector2(98, 4)), Color("121719"))
			draw_rect(Rect2(c + Vector2(-49, 49), Vector2(98 * level, 4)), Color("dc8766") if level >= 0.66 else Color("91a99a"))
		else:
			word(c + Vector2(-26, 12), "EMPTY", MUTED, 12)

func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(14)
	return box
