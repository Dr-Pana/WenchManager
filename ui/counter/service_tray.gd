extends Control
## Draw staged goods and individual coins; these are previews until settlement.
signal item_removed(product: String)
var items: Dictionary = {}
var coins: Array[int] = []
var hit_items: Array[Dictionary] = []
const COLORS := {"cheap ale": Color("c49b53"), "cheap wine": Color("a26376"), "strong ale": Color("ad7447"), "mead": Color("d6b973"), "good wine": Color("9e86bd")}

func _ready() -> void:
	custom_minimum_size.y = 105
	resized.connect(queue_redraw)
	tooltip_text = "Click a prepared drink to return it to the shelf. Stock is spent only when served."

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for entry in hit_items:
			if entry["rect"].has_point(event.position):
				item_removed.emit(entry["product"])
				accept_event()
				return

func _draw() -> void:
	hit_items.clear()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1b2427")
	style.set_corner_radius_all(12)
	style.border_color = Color("695341")
	style.set_border_width_all(2)
	draw_style_box(style, Rect2(Vector2.ZERO, size))
	var index := 0
	for product in items:
		for count in int(items[product]):
			var columns := maxi(1, int((size.x - 20) / 30))
			var pos := Vector2(14 + (index % columns) * 30, 13 + int(index / columns) * 33)
			draw_arc(pos + Vector2(19, 14), 8, -PI / 2, PI / 2, 12, Color("aa9981"), 3)
			draw_rect(Rect2(pos, Vector2(20, 27)), Color("d6c4a2"))
			draw_rect(Rect2(pos + Vector2(3, 4), Vector2(14, 19)), COLORS.get(product, Color.WHITE))
			hit_items.append({"rect": Rect2(pos, Vector2(25, 28)), "product": product})
			index += 1
	if index == 0:
		draw_string(ThemeDB.fallback_font, Vector2(15, 30), "Place drinks here", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("8c928c"))
	var coin_x := 16.0
	for value in coins:
		if coin_x > size.x - 20: break
		var pos := Vector2(coin_x, size.y - 17)
		draw_circle(pos, 11, Color("cba35d"))
		draw_arc(pos, 8, 0, TAU, 24, Color("f4d694"), 1)
		draw_string(ThemeDB.fallback_font, pos + Vector2(-4, 5), str(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("493725"))
		coin_x += 26
