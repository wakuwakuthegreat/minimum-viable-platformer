extends CanvasLayer

const FONT_KA1 := preload("res://assets/fonts/ka1.ttf")

@onready var root: Control = $Root
@onready var dist_label: Label = $Root/Bar/Distance
@onready var tokens_label: Label = $Root/Bar/Tokens
@onready var best_label: Label = $Root/Bar/Best

var _shown: bool = false
var _last_tokens: int = 0
var _last_dist: int = -1
var _last_best: int = -1
var _last_gained: int = -1
var _last_mult: int = -1
var _mult_label: Label = null
var _best_flag: Label = null   # rotated side indicator
var _best_flag_state: String = ""    # last committed state ("", "ALMOST!", "NEW BEST!")
var _best_flag_intro_played: bool = false
var _run_tokens_label: Label = null   # "+N ★" live run gain

func _ready() -> void:
	layer = 95
	_shown = Global.is_unlocked("hud")
	visible = _shown
	if not _shown: return
	UITheme.apply_current(self)
	_last_tokens = Global.tokens
	tokens_label.text = "★ %d" % _last_tokens
	root.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.35).set_delay(0.10)

	_build_mult_label()
	_build_best_flag()
	_build_run_tokens_label()

func _build_mult_label() -> void:
	_mult_label = Label.new()
	_mult_label.add_theme_font_override("font", FONT_KA1)
	_mult_label.add_theme_font_size_override("font_size", 34)
	_mult_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	_mult_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08))
	_mult_label.add_theme_constant_override("outline_size", 6)
	_mult_label.text = ""
	_mult_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root/Bar.add_child(_mult_label)

func _build_run_tokens_label() -> void:
	_run_tokens_label = Label.new()
	_run_tokens_label.add_theme_font_override("font", FONT_KA1)
	_run_tokens_label.add_theme_font_size_override("font_size", 22)
	_run_tokens_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.30))
	_run_tokens_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08))
	_run_tokens_label.add_theme_constant_override("outline_size", 5)
	_run_tokens_label.text = ""
	_run_tokens_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Place it below the tokens label inside the Bar container.
	$Root/Bar.add_child(_run_tokens_label)

func _build_best_flag() -> void:
	_best_flag = Label.new()
	_best_flag.text = ""
	_best_flag.add_theme_font_override("font", FONT_KA1)
	_best_flag.add_theme_font_size_override("font_size", 28)
	_best_flag.add_theme_color_override("font_color", Color(1, 1, 1))
	_best_flag.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08))
	_best_flag.add_theme_constant_override("outline_size", 6)
	_best_flag.rotation_degrees = -90.0
	_best_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_best_flag.custom_minimum_size = Vector2(240, 40)
	_best_flag.position = Vector2(48, get_viewport().get_visible_rect().size.y * 0.5 + 120)
	_best_flag.visible = false
	_best_flag.modulate.a = 0.0
	_best_flag.pivot_offset = _best_flag.custom_minimum_size * 0.5
	root.add_child(_best_flag)
	_best_flag_state = ""
	_best_flag_intro_played = false


func _process(_delta: float) -> void:
	if not _shown: return
	# Rebuild each string only when its number changes — formatting four
	# strings every frame is steady garbage on a phone for text that mostly
	# sits still.
	if Global.last_run_distance != _last_dist:
		_last_dist = Global.last_run_distance
		dist_label.text = "▶ %d m" % _last_dist
	if Global.best_distance != _last_best:
		_last_best = Global.best_distance
		best_label.text = "best %d m" % _last_best
	if Global.tokens != _last_tokens:
		_last_tokens = Global.tokens
		tokens_label.text = "★ %d" % _last_tokens
		var tw = create_tween()
		tw.tween_property(tokens_label, "scale", Vector2(1.4, 1.4), 0.10).set_trans(Tween.TRANS_BACK)
		tw.tween_property(tokens_label, "scale", Vector2.ONE, 0.20)
	# Live run token gain counter.
	if _run_tokens_label and Global.run_tokens_gained != _last_gained:
		_last_gained = Global.run_tokens_gained
		_run_tokens_label.text = ("+%d ★" % _last_gained) if _last_gained > 0 else ""

	# Combo multiplier chip.
	if _mult_label:
		var m: int = ComboSystem.current_multiplier()
		if m != _last_mult:
			_last_mult = m
			_mult_label.text = ("x%d" % m) if m >= 1 else ""
			_mult_label.visible = m >= 1

	_update_best_flag()

func _update_best_flag() -> void:
	if _best_flag == null: return
	var score := Global.current_run_score
	var ever := Global.best_score_ever
	var seed_best := Global.current_seed_best_score

	# Only compute a state if the run has actually produced score. Prevents any
	# residual "ALMOST!" state at the very start of a run when score is zero but
	# thresholds happen to be zero too.
	var state := ""
	var beat := false
	if score > 0:
		# Priority: beat ever > beat seed > almost either. Threshold tightened to
		# 94% so ALMOST doesn't linger for an entire run after just crossing 90%.
		if ever > 0 and score > ever:
			state = "NEW BEST!"; beat = true
		elif seed_best > 0 and score > seed_best:
			state = "NEW BEST!"; beat = true
		elif ever > 0 and score >= int(ever * 0.94):
			state = "ALMOST!"
		elif seed_best > 0 and score >= int(seed_best * 0.94):
			state = "ALMOST!"

	if state != _best_flag_state:
		_best_flag_state = state
		if state == "":
			# Fade out; keep it invisible until a new state fires.
			var tw_out := create_tween()
			tw_out.tween_property(_best_flag, "modulate:a", 0.0, 0.25)
			tw_out.tween_callback(func(): _best_flag.visible = false)
			return
		# Entering a new state — play the intro pop once.
		_best_flag.visible = true
		_best_flag.text = state
		_best_flag.scale = Vector2(0.4, 0.4)
		_best_flag.modulate.a = 0.0
		var tw_in := create_tween()
		tw_in.tween_property(_best_flag, "modulate:a", 1.0, 0.20)
		tw_in.parallel().tween_property(_best_flag, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_best_flag_intro_played = true

	if state == "":
		return

	# Idle animation once the flag is committed.
	var t = Time.get_ticks_msec() * 0.001
	if beat:
		var hue = fmod(t * 0.4, 1.0)
		_best_flag.add_theme_color_override("font_color", Color.from_hsv(hue, 0.85, 1.0))
	else:
		_best_flag.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	var pulse := 1.0 + 0.05 * sin(t * (5.0 if beat else 3.0))
	# Blend the intro tween's scale toward the pulse without ever fighting it.
	if _best_flag.scale.x >= 0.9:
		_best_flag.scale = Vector2(pulse, pulse)
