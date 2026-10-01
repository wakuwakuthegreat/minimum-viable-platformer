extends CanvasLayer

## First-time tutorial overlay. Shows a black splash screen then a series of
## narrative slides. Emits `finished` when the player taps through all slides.
## Easy to edit: just update SLIDES below.

signal finished

# ─── EDIT THESE TO CHANGE THE TUTORIAL ─────────────────────────────────────
## Optional "who" pulls font/size/colour from StoryDB.VOICES, so the intro speaks
## in the same voices as the later story cuts. Omit it for the neutral look.
const SLIDES: Array = [
	# too chatty
	{
		"who":   "narrator",
		"title": "WELCOME FRIENDS!",
		"body":  "Welcome to a happy world of challenge!\nGrab your best friends and get ready to smile.",
		"icon":  "♥",
	},
	{
		"who":   "narrator",
		"title": "JOYFUL JUMPING",
		"body":  "Tap to jump. Tap longer to jump higher.\nAvoid the pointy hugs, or bounce on their heads for a fun boost.\nThey just want to be close to you. Forever.",
		"icon":  "↑",
	},
	#{
		#"who":   "princess",
		#"title": "oh, a NEW one",
		#"body":  "Hello! You're the forty-thousandth today.\nDon't listen to the tall voice, it reads from a script it hasn't finished.\nI'll be over here. Being decorative. Allegedly.",
		#"icon":  "❀",
	#},
	#{
		#"who":   "soul",
		#"title": "listen",
		#"body":  "none of this belongs to him\nhe borrowed the whole thing and he is going to ask for it back\nplease remember i said it first",
		#"icon":  "◌",
	#},
	{
		"who":   "narrator",
		"title": "WE GAVE YOU EVERYTHING",
		"body":  "Enjoy this fully developed, perfectly safe experience.",
		"icon":  "★",
	}
]
# ─────────────────────────────────────────────────────────────────────────────

const FONT_KA1 := preload("res://assets/fonts/ka1.ttf")
const FONT_NERVOUS := preload("res://assets/fonts/Nervous.ttf")
const BG_COLOR    := Color(0.04, 0.03, 0.08)
const TITLE_COLOR := Color(1.00, 0.90, 0.40)
const BODY_COLOR  := Color(0.88, 0.84, 0.92)
const ICON_COLOR  := Color(0.60, 0.90, 1.00)
const HINT_COLOR  := Color(0.45, 0.42, 0.52)
const DOT_ACTIVE  := Color(1.00, 0.85, 0.30)
const DOT_IDLE    := Color(0.30, 0.27, 0.38)

var _slide_idx: int = -1   # -1 = black splash, 0+ = tutorial slides
var _can_advance: bool = false
var _advancing: bool = false
var _typing: bool = false
var _typewriter_tw: Tween = null
var _last_input_frame: int = -1

# UI nodes built in code so no .tscn dependency.
var _bg: ColorRect = null
var _icon_label: Label = null
var _title_label: Label = null
var _body_label: Label = null
var _hint_label: Label = null
var _dot_row: HBoxContainer = null
var _dots: Array = []

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_build_ui()
	_show_splash()

# ─── BUILD ───────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.color = BG_COLOR
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(520, 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	_icon_label = Label.new()
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_override("font", FONT_KA1)
	_icon_label.add_theme_font_size_override("font_size", 64)
	_icon_label.add_theme_color_override("font_color", ICON_COLOR)
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_icon_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_font_override("font", FONT_KA1)
	_title_label.add_theme_font_size_override("font_size", 32)
	_title_label.add_theme_color_override("font_color", TITLE_COLOR)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_override("font", FONT_NERVOUS)
	_body_label.add_theme_font_size_override("font_size", 26)
	_body_label.add_theme_color_override("font_color", BODY_COLOR)
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_body_label)

	# Progress dots
	_dot_row = HBoxContainer.new()
	_dot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_dot_row.add_theme_constant_override("separation", 14)
	_dot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in SLIDES.size():
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 18)
		dot.add_theme_color_override("font_color", DOT_IDLE)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dot_row.add_child(dot)
		_dots.append(dot)
	vbox.add_child(_dot_row)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 17)
	_hint_label.add_theme_color_override("font_color", HINT_COLOR)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hint_label)

# ─── SPLASH ──────────────────────────────────────────────────────────────────

func _show_splash() -> void:
	_slide_idx = -1
	_icon_label.text = "◈"
	_title_label.text = "MINIMUM VIABLE PLATFORMER"
	_body_label.text = ""
	_dot_row.visible = false
	_hint_label.text = "tap to begin"
	_bg.modulate.a = 1.0
	_icon_label.modulate.a = 0.0
	_title_label.modulate.a = 0.0
	_hint_label.modulate.a = 0.0
	_can_advance = false
	var tw := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(_title_label, "modulate:a", 1.0, 0.50)
	tw.tween_property(_icon_label, "modulate:a", 1.0, 0.35)
	tw.tween_interval(0.3)
	tw.tween_property(_hint_label, "modulate:a", 1.0, 0.40)
	tw.tween_callback(func(): _can_advance = true)

# ─── SLIDES ──────────────────────────────────────────────────────────────────

func _show_slide(idx: int) -> void:
	_slide_idx = idx
	_dot_row.visible = true
	var s: Dictionary = SLIDES[idx]
	_can_advance = false
	var tw := create_tween().set_parallel(false)
	# Fade out current content.
	tw.tween_property(_icon_label,  "modulate:a", 0.0, 0.12)
	tw.parallel().tween_property(_title_label, "modulate:a", 0.0, 0.12)
	tw.parallel().tween_property(_body_label,  "modulate:a", 0.0, 0.12)
	tw.parallel().tween_property(_hint_label,  "modulate:a", 0.0, 0.10)
	# Swap content.
	tw.tween_callback(func():
		_icon_label.text  = s.get("icon", "▶")
		_title_label.text = s.get("title", "")
		_body_label.text  = s.get("body", "")
		_body_label.visible_characters = 0
		_hint_label.text  = "tap to continue" if idx < SLIDES.size() - 1 else "tap to play"
		_apply_voice(s.get("who", ""))
		_update_dots(idx)
	)
	# Fade in.
	tw.tween_property(_icon_label,  "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(_title_label, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(_body_label,  "modulate:a", 1.0, 0.22)
	tw.tween_callback(func():
		_typing = true
		_typewriter_tw = create_tween()
		var char_count = _body_label.text.length()
		var char_interval := 0.04
		# Queue one tick sound per character using individual tween steps.
		for ci in char_count:
			_typewriter_tw.tween_callback(func():
				_body_label.visible_characters = ci + 1
				if fmod(ci, 1) == 0:
					AudioManager.play("tick", -8.0, 0.06)
			)
			_typewriter_tw.tween_interval(char_interval)
		_typewriter_tw.tween_callback(func():
			_body_label.visible_characters = char_count
			_typing = false
			_can_advance = true
			var hint_tw := create_tween()
			hint_tw.tween_property(_hint_label, "modulate:a", 0.70, 0.22)
		)
	)

func _update_dots(active: int) -> void:
	for i in _dots.size():
		_dots[i].add_theme_color_override("font_color", DOT_ACTIVE if i == active else DOT_IDLE)

## Restyle the slide in a StoryDB voice. Falls back to the neutral look when the
## slide has no "who" (or names one that doesn't exist).
func _apply_voice(who: String) -> void:
	if who == "" or not StoryDB.VOICES.has(who):
		_title_label.add_theme_font_override("font", FONT_KA1)
		_title_label.add_theme_color_override("font_color", TITLE_COLOR)
		_body_label.add_theme_font_override("font", FONT_NERVOUS)
		_body_label.add_theme_font_size_override("font_size", 26)
		_body_label.add_theme_color_override("font_color", BODY_COLOR)
		_icon_label.add_theme_color_override("font_color", ICON_COLOR)
		return
	var v: Dictionary = StoryDB.voice(who)
	var col: Color = v.get("color", BODY_COLOR)
	var font: Font = v.get("font", FONT_NERVOUS)
	_title_label.add_theme_font_override("font", font)
	_title_label.add_theme_color_override("font_color", col.lerp(TITLE_COLOR, 0.25))
	_body_label.add_theme_font_override("font", font)
	_body_label.add_theme_font_size_override("font_size", int(v.get("size", 26)) - 2)
	_body_label.add_theme_color_override("font_color", col)
	_icon_label.add_theme_color_override("font_color", col)

# ─── ADVANCE / FINISH ────────────────────────────────────────────────────────

func _advance() -> void:
	if not _can_advance or _advancing: return
	_advancing = true
	if _slide_idx < 0:
		# Splash → first slide
		_advancing = false
		_show_slide(0)
	elif _slide_idx < SLIDES.size() - 1:
		# Next slide
		_advancing = false
		_show_slide(_slide_idx + 1)
	else:
		# Last slide → finish
		_can_advance = false
		# Do NOT set tutorial_seen here. We need the "fake run" to stay unlocked
		# until the player dies, at which point the death sequence sets it.
		var tw := create_tween()
		tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_property(_bg, "modulate:a", 0.0, 0.45)
		tw.tween_callback(func():
			get_tree().paused = false
			queue_free()
			emit_signal("finished")
		)

# ─── INPUT ───────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	var is_tap := false
	
	if event is InputEventScreenTouch and event.pressed:
		is_tap = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_tap = true
	elif event is InputEventKey and event.pressed and not event.echo:
		is_tap = true
	if not is_tap:
		return
	var frame := Engine.get_process_frames()
	if frame == _last_input_frame:
		return
	_last_input_frame = frame
	if _typing:
		if _typewriter_tw:
			_typewriter_tw.kill()
			_typewriter_tw = null
		_body_label.visible_characters = -1
		_typing = false
		_can_advance = true
		var hint_tw := create_tween()
		hint_tw.tween_property(_hint_label, "modulate:a", 0.70, 0.1)
	else:
		_advance()
