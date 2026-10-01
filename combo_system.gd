extends CanvasLayer

## Airtime + stomp combo system. Autoloaded.
##
## Multiplier is time-based: every COMBO_TICK_SECS of an active combo adds +1.
## Stomping enemies with a combo_bonus adds instantly (bouncy +2, super +10).
## While active, tokens earned are scaled by the multiplier (via
## Global.token_multiplier).
##
## The floating "xN / airtime" popup pins to the top-right and is gated behind
## the `combo_system` skill. Bounce transition is opt-in via `combo_bounce`.

const FONT_KA1  := preload("res://assets/fonts/ka1.ttf")
const FONT_FUNK := preload("res://assets/fonts/funkymuskrat.ttf")

const COMBO_TICK_SECS := 1.5
const STOMP_WORDS := ["STOMP!", "BOOM!", "POW!", "GOTCHA!", "ZAP!", "WHACK!", "OJ!", "SPLAT!"]

# Praise words shown near the player each time the combo ticks up. Buckets
# escalate with the multiplier — bigger words + bigger font as the streak grows.
const PRAISE_TIERS := [
	["Fresh!",   "Nice!",    "Neat!",    "Sweet!",    "Snappy!"],
	["Juicy!",   "Slick!",   "Groovy!",  "Cooking!",  "Zesty!"],
	["Sizzling!","Toasty!",  "On Fire!", "Blazing!",  "Spicy!"],
	["Developed!","Refined!","Polished!","Vintage!",  "Mastered!"],
	["INFERNO!", "MELTDOWN!","SUPERNOVA!","COSMIC!",  "GODLIKE!"],
]
const PRAISE_FONT_SIZE_MIN := 44
const PRAISE_FONT_SIZE_STEP := 6   # +6px per multiplier tick

var _airborne: bool = false
var _combo_active: bool = false
var _combo_start_ms: int = 0
var _bonus: int = 0            # accumulated stomp bonuses this combo
var _multiplier: int = 0       # last computed integer multiplier
var _last_tick_shown: int = 0

# x-stall detection: end combo if player hasn't moved horizontally for this long.
const X_STALL_SECS := 0.5
const X_MOVE_EPS   := 2.0   # pixels; ignores floating-point jitter
var _last_player_x: float = INF
var _x_stall_timer: float = 0.0

var _live_popup: Label = null  # persistent big-xN popup while active
var _popup_shown_for: int = 0  # highest multiplier the popup has been animated for
var _record_celebrated: int = 0  # highest longest_combo we've already congratulated this session

# ─── WIND EFFECT ─────────────────────────────────────────────────────────────
const WIND_COMBO_THRESHOLD := 3
var _wind_on: bool = false
# Pool of wind-line Line2Ds reused each spawn cycle.
var _wind_lines: Array[Line2D] = []
var _wind_line_data: Array = []   # [{age, speed, y, length, alpha}]
const WIND_LINE_COUNT := 14
const WIND_LINE_SPEED_MIN := 900.0
const WIND_LINE_SPEED_MAX := 1600.0

func _ready() -> void:
	layer = 80
	set_process(true)
	_setup_wind_lines()

func _setup_wind_lines() -> void:
	for i in WIND_LINE_COUNT:
		var ln := Line2D.new()
		ln.width = 3.0
		ln.default_color = Color(1.0, 1.0, 1.0, 0.0)
		ln.z_index = 50
		ln.visible = false
		add_child(ln)
		_wind_lines.append(ln)
		_wind_line_data.append({"age": INF, "speed": 1200.0, "y": 0.0, "length": 140.0, "x": -200.0})
	# Stagger initial positions so they don't all spawn simultaneously.
	for i in WIND_LINE_COUNT:
		_wind_line_data[i]["age"] = randf() * 3.0

func _gated() -> bool:
	return Global.is_unlocked("combo_system")

## External read for HUD / token scaling.
func current_multiplier() -> int:
	return _multiplier if _combo_active else 0

## Multiplicative bonus applied to earned tokens while a combo is live.
func token_multiplier() -> int:
	return max(1, current_multiplier())

func notify_airborne(is_air: bool) -> void:
	if not _gated(): return
	if is_air and not _airborne:
		_airborne = true
		if not _combo_active:
			_begin_combo()
	elif not is_air and _airborne:
		_airborne = false
		# End combo on landing.
		_end_combo()

func notify_stomp(world_pos: Vector2, combo_bonus: int = 0) -> void:
	if not _gated(): return
	if not _combo_active:
		_begin_combo()
	_bonus += combo_bonus
	# Stomping mid-combo re-arms the "airborne" state so a bounce continues it.
	_airborne = true
	_recompute_multiplier()
	_track_longest_combo(_multiplier)
	# Score bonus from the stomp itself, scaled by mult.
	Global.add_run_score(50 * token_multiplier())
	var word: String = STOMP_WORDS[randi() % STOMP_WORDS.size()]
	_spawn_side_popup(world_pos, word)

## Hard reset. Called on player death and new-run start so combo state never
## leaks across lives or runs.
func reset() -> void:
	_airborne = false
	_bonus = 0
	_multiplier = 0
	_last_tick_shown = 0
	_combo_active = false
	_last_player_x = INF
	_x_stall_timer = 0.0
	if _live_popup and is_instance_valid(_live_popup):
		_live_popup.queue_free()
	_live_popup = null
	_set_wind(false)

func _set_wind(active: bool) -> void:
	if _wind_on == active: return
	_wind_on = active
	AudioManager.set_wind_audio(active)

func _begin_combo() -> void:
	_combo_active = true
	_combo_start_ms = Time.get_ticks_msec()
	_bonus = 0
	_multiplier = 0
	_last_tick_shown = 0
	_popup_shown_for = 0
	_popup_base_pos = Vector2.ZERO
	_popup_hue_t = 0.0
	_last_player_x = INF
	_x_stall_timer = 0.0

func _end_combo() -> void:
	_combo_active = false
	_multiplier = 0
	_bonus = 0
	_last_tick_shown = 0
	if _live_popup and is_instance_valid(_live_popup):
		var pop = _live_popup
		_live_popup = null
		var tw = create_tween()
		tw.tween_property(pop, "modulate:a", 0.0, 0.25)
		tw.tween_callback(pop.queue_free)
	_set_wind(false)

func _elapsed_secs() -> float:
	return (Time.get_ticks_msec() - _combo_start_ms) / 1000.0

func _recompute_multiplier() -> void:
	var mult = int(floor(_elapsed_secs() / COMBO_TICK_SECS)) + _bonus
	if mult > _multiplier:
		var jumped = mult - _multiplier
		_multiplier = mult
		# Frame freeze on tick if impact_freeze is unlocked.
		# Only freeze on combo start
		if Global.is_unlocked("impact_freeze") and mult < 2:
			Engine.time_scale = 0.015
			var t = get_tree().create_timer(0.105, true, false, true)
			t.timeout.connect(func(): Engine.time_scale = 1.0)
		_last_tick_shown = _multiplier
	else:
		_multiplier = mult

func _process(delta: float) -> void:
	_tick_wind_lines(delta)
	if not _combo_active: return
	_recompute_multiplier()
	if _multiplier >= 1:
		if _live_popup == null or not is_instance_valid(_live_popup):
			_live_popup = _make_live_popup()
			add_child(_live_popup)
		_update_live_popup()
		_style_live_popup(delta)
		if _multiplier > _popup_shown_for:
			_popup_shown_for = _multiplier
			_impact_popup(_live_popup)
			_spawn_praise_popup(_multiplier)
	# Activate wind when combo exceeds threshold.
	_set_wind(_multiplier > WIND_COMBO_THRESHOLD)
	# End combo if grace period elapses without airborne / bonus refresh.
	if not _airborne and _elapsed_secs() > 0.35 and _bonus == 0:
		_end_combo()
		return
	# End combo if player has been stationary on x for too long (e.g. stuck against wall).
	# Global.player is set by the player itself — no per-frame group scan.
	var pl = Global.player
	if pl != null and is_instance_valid(pl):
		var px: float = (pl as Node2D).global_position.x
		if _last_player_x == INF:
			_last_player_x = px
		elif abs(px - _last_player_x) > X_MOVE_EPS:
			_last_player_x = px
			_x_stall_timer = 0.0
		else:
			_x_stall_timer += delta
			if _x_stall_timer >= X_STALL_SECS:
				_end_combo()

func _tick_wind_lines(delta: float) -> void:
	if not Global.is_unlocked("wind_effect"): return
	var vp_size := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	for i in WIND_LINE_COUNT:
		var d: Dictionary = _wind_line_data[i]
		var ln: Line2D = _wind_lines[i]
		if not _wind_on:
			if d["age"] == INF:
				ln.visible = false
				continue
		d["age"] = d.get("age", INF) + delta
		# Each line lives for a travel time then is respawned.
		var travel_time: float = (vp_size.x + d["length"]) / d["speed"]
		if d["age"] > travel_time:
			if not _wind_on:
				ln.visible = false
				d["age"] = INF
				continue
			# Spawn a fresh line at a random Y.
			d["speed"] = randf_range(WIND_LINE_SPEED_MIN, WIND_LINE_SPEED_MAX)
			d["length"] = randf_range(60.0, 240.0)
			d["y"] = randf_range(vp_size.y * 0.05, vp_size.y * 0.95)
			d["x"] = -d["length"]
			d["age"] = 0.0
		var x: float = d["x"] + d["speed"] * d["age"]
		# Fade in from left edge, fade out to right edge.
		var alpha: float = 1.0
		var fade_dist: float = 120.0
		if x < fade_dist:
			alpha = clamp(x / fade_dist, 0.0, 1.0)
		elif x > vp_size.x - fade_dist:
			alpha = clamp((vp_size.x - x) / fade_dist, 0.0, 1.0)
		var base_alpha: float = 0.55 if _multiplier >= 5 else 0.35
		ln.clear_points()
		ln.add_point(Vector2(x, d["y"]))
		ln.add_point(Vector2(x + d["length"], d["y"]))
		ln.default_color = Color(1.0, 1.0, 1.0, base_alpha * alpha)
		ln.visible = alpha > 0.01

## Heat + rainbow + jitter drive the live popup's paint each frame so the
## number visibly gets more unhinged as the combo climbs.
##   x1-x2 : warm yellow
##   x3    : orange
##   x4    : red / hot pink
##   x5+   : rainbow hue cycling
##   x6+   : positional jitter
var _popup_base_pos: Vector2 = Vector2.ZERO
var _popup_hue_t: float = 0.0
func _style_live_popup(delta: float) -> void:
	if _live_popup == null: return
	_popup_hue_t += delta
	var col: Color
	if _multiplier >= 5:
		# Rainbow: cycle hue over ~1.2s, keep punchy saturation/value.
		var hue := fposmod(_popup_hue_t * 0.85, 1.0)
		col = Color.from_hsv(hue, 0.85, 1.0)
	else:
		# Interpolate heat ramp yellow -> orange -> red -> hot pink.
		var ramp := [
			Color(1.00, 0.85, 0.20),  # x1 warm yellow
			Color(1.00, 0.85, 0.20),  # x2
			Color(1.00, 0.60, 0.15),  # x3 orange
			Color(1.00, 0.30, 0.20),  # x4 red
			Color(1.00, 0.20, 0.55),  # x5 hot pink (never reached, capped by rainbow)
		]
		var idx: int = clamp(_multiplier - 1, 0, ramp.size() - 1)
		col = ramp[idx]
	_live_popup.add_theme_color_override("font_color", col)

	# Jitter at x6+.
	if _popup_base_pos == Vector2.ZERO:
		_popup_base_pos = _live_popup.position
	if _multiplier >= 6:
		var amt: float = 3.0 + float(_multiplier - 6) * 1.2
		_live_popup.position = _popup_base_pos + Vector2(
			randf_range(-amt, amt), randf_range(-amt, amt))
	else:
		_live_popup.position = _popup_base_pos

func _make_live_popup() -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.add_theme_font_override("font", FONT_KA1)
	label.add_theme_font_size_override("font_size", 60)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08))
	label.add_theme_constant_override("outline_size", 8)
	label.z_index = 100
	label.modulate.a = 0.0
	var vp := get_viewport().get_visible_rect().size
	label.size = Vector2(360, 130)
	label.pivot_offset = label.size * 0.5
	label.position = Vector2(vp.x - label.size.x - 32, 90)
	label.scale = Vector2(0.6, 0.6)
	return label

## Impact tween played every time the multiplier ticks up: zoom in from a
## bigger scale and pop in opacity so the number feels like it's slamming
## onto the screen. Kills any prior tween on the label to avoid pile-up.
func _impact_popup(label: Label) -> void:
	if label == null or not is_instance_valid(label): return
	label.scale = Vector2(1.8, 1.8)
	label.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(label, "modulate:a", 1.0, 0.12)
	var trans := Tween.TRANS_BACK if Global.is_unlocked("combo_bounce") else Tween.TRANS_CUBIC
	tw.tween_property(label, "scale", Vector2.ONE, 0.28) \
		.set_trans(trans).set_ease(Tween.EASE_OUT)

func _update_live_popup() -> void:
	if _live_popup == null: return
	var big := "x%d" % _multiplier
	var small := "%.1fs" % _elapsed_secs()
	# Two-line label: big on top, smaller time underneath. Uses BBCode-free
	# Label so we approximate size difference with newline + note.
	_live_popup.text = "%s\n%s" % [big, small]

func _spawn_side_popup(world_pos: Vector2, text: String, font_size: int = 48, color: Color = Color(1.0, 0.85, 0.2)) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT_FUNK)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08))
	label.add_theme_constant_override("outline_size", 8)
	label.z_index = 100

	var vp := get_viewport()
	var vp_size := vp.get_visible_rect().size
	var w: float = max(280.0, float(font_size) * 8.0)
	var h: float = max(84.0, float(font_size) * 1.8)
	label.size = Vector2(w, h)
	label.pivot_offset = label.size * 0.5
	var canvas_xform := vp.get_canvas_transform()
	var screen_pos := canvas_xform * (world_pos + Vector2(0, -160))
	var target_pos: Vector2 = screen_pos - Vector2(label.size.x * 0.5, label.size.y * 0.5)
	target_pos.x = clamp(target_pos.x, 24, vp_size.x - label.size.x - 24)
	target_pos.y = clamp(target_pos.y, 60, vp_size.y - label.size.y - 60)
	label.position = target_pos
	label.rotation_degrees = randf_range(-8.0, 8.0)
	label.modulate.a = 0.0
	add_child(label)

	var tw := create_tween().set_parallel(true)
	if Global.is_unlocked("combo_bounce"):
		label.scale = Vector2(0.4, 0.4)
		tw.tween_property(label, "scale", Vector2(1.15, 1.15), 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 1.0, 0.12)
	var tw2 := create_tween()
	tw2.tween_interval(0.45)
	tw2.tween_property(label, "position:y", label.position.y - 80.0, 0.45)
	var tw3 := create_tween()
	tw3.tween_interval(0.45)
	tw3.tween_property(label, "modulate:a", 0.0, 0.30)
	tw3.tween_callback(label.queue_free)

## Picks a bucketed praise word and spawns it near the player. Word list and
## font size scale with the multiplier — deeper streaks get louder text.
func _spawn_praise_popup(mult: int) -> void:
	var tier: int = clamp((mult - 1) / 2, 0, PRAISE_TIERS.size() - 1)
	var pool: Array = PRAISE_TIERS[tier]
	var word: String = String(pool[randi() % pool.size()])
	var font_size: int = PRAISE_FONT_SIZE_MIN + PRAISE_FONT_SIZE_STEP * (mult - 1)
	var col: Color
	if mult >= 5:
		col = Color.from_hsv(fposmod(_popup_hue_t * 0.85, 1.0), 0.8, 1.0)
	else:
		col = _live_popup.get_theme_color("font_color") if _live_popup else Color(1.0, 0.85, 0.2)
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty(): return
	var p: Node2D = players[0]
	_spawn_side_popup(p.global_position, word, font_size, col)

func _track_longest_combo(value: int) -> void:
	Global.current_run_highest_combo = max(Global.current_run_highest_combo, value)
	var prior := int(Global.stats.get("longest_combo", 0))
	Global.stat_max("longest_combo", value)
	# Congratulate the first time we beat the prior record this session.
	# `_record_celebrated` gates repeats so a x9 combo doesn't spam once per tick.
	if value > prior and value > _record_celebrated and prior > 0:
		_record_celebrated = value
		_spawn_record_popup(value)

func _spawn_record_popup(value: int) -> void:
	var label := Label.new()
	label.text = "NEW BEST!  x%d" % value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT_KA1)
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	label.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.2))
	label.add_theme_constant_override("outline_size", 10)
	label.z_index = 120
	var vp := get_viewport().get_visible_rect().size
	label.size = Vector2(560, 100)
	label.pivot_offset = label.size * 0.5
	label.position = Vector2((vp.x - label.size.x) * 0.5, vp.y * 0.35)
	label.modulate.a = 0.0
	label.scale = Vector2(0.5, 0.5)
	add_child(label)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(label, "modulate:a", 1.0, 0.18)
	tw.tween_property(label, "scale", Vector2(1.15, 1.15), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw2 := create_tween()
	tw2.tween_interval(1.1)
	tw2.tween_property(label, "position:y", label.position.y - 60.0, 0.5)
	tw2.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tw2.tween_callback(label.queue_free)
