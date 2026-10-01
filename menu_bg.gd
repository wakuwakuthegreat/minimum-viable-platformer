extends Control

## Draws the menu backdrop. Polished theme = warm cream sky + parallax hills;
## placeholder theme = flat dark grey.

@export var theme_name: String = ""   # auto if empty

var _t: float = 0.0
var _hill_seeds: Array[float] = []

func _ready() -> void:
	# Pre-generate per-instance random offsets so the hills look organic but stable.
	var rng = RandomNumberGenerator.new()
	rng.seed = 1337
	for i in 64:
		_hill_seeds.append(rng.randf())
	resized.connect(queue_redraw)
	set_process(true)
	queue_redraw()

func _resolved_theme() -> String:
	if theme_name != "": return theme_name
	return UITheme.current_theme_name()

func _process(delta: float) -> void:
	if _resolved_theme() == "polished":
		_t += delta * 8.0
		queue_redraw()

func _draw() -> void:
	var sz = size
	if _resolved_theme() == "placeholder":
		# Sleek minimalist slate gradient with faint blueprint grid
		var bg_top := Color(0.14, 0.15, 0.18)
		var bg_bot := Color(0.08, 0.08, 0.10)
		var bands = 16
		for i in bands:
			var ty = float(i) / float(bands)
			var col = bg_top.lerp(bg_bot, ty)
			draw_rect(Rect2(0, sz.y * ty, sz.x, sz.y / bands + 1.0), col, true)

		# Faint minimalist blueprint grid
		var grid_col := Color(1.0, 1.0, 1.0, 0.035)
		var grid_step := 64.0
		var gx := 0.0
		while gx <= sz.x:
			draw_line(Vector2(gx, 0), Vector2(gx, sz.y), grid_col, 1.0)
			gx += grid_step
		var gy := 0.0
		while gy <= sz.y:
			draw_line(Vector2(0, gy), Vector2(sz.x, gy), grid_col, 1.0)
			gy += grid_step

		# Subtle bottom anchor bar
		draw_line(Vector2(0, sz.y - 2.0), Vector2(sz.x, sz.y - 2.0), Color(1.0, 1.0, 1.0, 0.08), 2.0)
		return

	# ─── Polished: warm sky → peach gradient ───────────────────────
	var top_col = Color(1.0, 0.92, 0.78)
	var bot_col = Color(0.98, 0.78, 0.55)
	var bands = 32
	for i in bands:
		var ty = float(i) / float(bands)
		var col = top_col.lerp(bot_col, ty)
		draw_rect(Rect2(0, sz.y * ty, sz.x, sz.y / bands + 1), col, true)

	# Distant hills (slow parallax via _t)
	_draw_hills(sz, 0.55, Color(0.93, 0.70, 0.42), 200.0, 0.2)
	_draw_hills(sz, 0.72, Color(0.85, 0.55, 0.30), 150.0, 0.6)
	# Foreground grass strip
	_draw_grass_strip(sz)

func _draw_hills(sz: Vector2, y_ratio: float, col: Color, amp: float, parallax_k: float) -> void:
	var poly = PackedVector2Array()
	var n = 80
	var baseline = sz.y * y_ratio
	poly.append(Vector2(0, sz.y))
	for i in n + 1:
		var x_norm = float(i) / float(n)
		var x = x_norm * sz.x
		var s1 = sin(x_norm * 6.28 * 1.5 + _t * parallax_k) * 0.5
		var s2 = sin(x_norm * 6.28 * 3.7 + _t * parallax_k * 0.4) * 0.3
		var y = baseline + (s1 + s2) * amp
		poly.append(Vector2(x, y))
	poly.append(Vector2(sz.x, sz.y))
	draw_colored_polygon(poly, col)

func _draw_grass_strip(sz: Vector2) -> void:
	var grass_top = sz.y * 0.86
	var poly = PackedVector2Array()
	poly.append(Vector2(0, sz.y))
	var n = 100
	for i in n + 1:
		var x_norm = float(i) / float(n)
		var x = x_norm * sz.x
		var s = sin(x_norm * 6.28 * 5.0 + _t * 1.4) * 8.0 + sin(x_norm * 6.28 * 11.0) * 4.0
		poly.append(Vector2(x, grass_top + s))
	poly.append(Vector2(sz.x, sz.y))
	draw_colored_polygon(poly, Color(0.60, 0.78, 0.32))

	# Darker bottom
	draw_rect(Rect2(0, sz.y * 0.92, sz.x, sz.y * 0.08), Color(0.36, 0.50, 0.20), true)
