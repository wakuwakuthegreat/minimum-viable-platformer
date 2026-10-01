extends CanvasLayer
## Plays a StoryDB scene — one dialog block on screen at a time, tap to advance.
## Tapping mid-typewriter completes the block; tapping again moves to the next.
##
##   var cut = preload("res://story_cut.gd").new()
##   get_tree().root.add_child(cut)
##   cut.finished.connect(_on_cut_finished)
##   cut.play(scene["blocks"], scene.get("mode", "black"))
##
## mode "black" = opaque lore cut (deaths, intro).
## mode "scrim" = darkened overlay so the live scene stays legible behind it.

signal finished

const BG_COLOR := Color(0.02, 0.01, 0.03)
const SCRIM_ALPHA := 0.80
const CUT_LAYER := 210

## ─── QUEUE ──────────────────────────────────────────────────────────────
## Two cuts can be asked for at once — a death milestone and an onboarding beat,
## say — and each call site just adds its own node to the root. Before this they
## drew on top of each other and both ate the same tap. Now only one is ever
## live; the rest wait in line and start the instant the one ahead closes.
## `finished` still fires when THIS cut ends, so `await cut.finished` keeps
## meaning exactly what it always did — it just may wait longer first.
static var _active: Object = null
static var _queue: Array = []

var _blocks: Array = []
var _mode: String = "black"
var _index: int = -1
var _typing: bool = false
var _accum: float = 0.0
var _char_time: float = 0.032
var _tick_db: float = -10.0
var _total: int = 0
var _shown: int = 0
var _last_input_frame: int = -1
var _closing: bool = false
var _prev_paused: bool = false
var _hint_tw: Tween = null
## False until this cut reaches the front of the queue and takes the screen.
var _started: bool = false

var _root: Control
var _bg: ColorRect
var _who: Label
var _body: RichTextLabel
var _hint: Label

func _ready() -> void:
	layer = CUT_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _active != null and is_instance_valid(_active) and _active != self:
		# Someone else has the screen. Stay dark and silent — no build, no pause,
		# and _input ignores us — until they hand it over.
		visible = false
		_queue.append(self)
		return
	_begin()

## Take the screen. The pause state is captured here rather than in _ready() so a
## cut that waited in line records the real pre-cut value instead of the pause its
## predecessor was still holding — otherwise queued cuts would leave the game
## frozen when the last one closed.
func _begin() -> void:
	_active = self
	_started = true
	visible = true
	_prev_paused = get_tree().paused
	get_tree().paused = true
	if _root == null:
		_build()
	if not _blocks.is_empty() and _index < 0:
		_show_block(0)

## Hand the screen to whoever is next in line. Called when this cut closes, and
## again from _exit_tree so a cut torn down some other way can't strand the queue.
func _release() -> void:
	if _active != self:
		_queue.erase(self)
		return
	_active = null
	while not _queue.is_empty():
		var nxt = _queue.pop_front()
		if nxt != null and is_instance_valid(nxt) and nxt.is_inside_tree():
			nxt._begin()
			return

func _exit_tree() -> void:
	_release()

## Queue a scene's blocks. Safe to call before or after the node enters the tree —
## and while queued, `_root` is still null, so this only records what to play.
## At most 2 characters speak per scene (excluding the game's opening cold open).
func play(blocks: Array, mode: String = "black") -> void:
	# Filter blocks to guarantee at most 2 speakers per session (except opening)
	var filtered_blocks: Array = []
	var allowed_speakers: Array[String] = []
	var is_opening: bool = false
	if blocks.size() > 4:
		# Check if this is the opening cold open with sponsor/princess/etc.
		for b in blocks:
			if b.get("text", "").begins_with("Welcome to your new platformer"):
				is_opening = true
				break

	if is_opening:
		filtered_blocks = blocks
	else:
		for b in blocks:
			var who: String = String(b.get("who", "narrator"))
			if not (who in allowed_speakers):
				if allowed_speakers.size() < 2:
					allowed_speakers.append(who)
					filtered_blocks.append(b)
			else:
				filtered_blocks.append(b)

	_blocks = filtered_blocks
	_mode = mode
	if _root != null:
		_apply_mode()
		if _index < 0 and not _blocks.is_empty():
			_show_block(0)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)

	var vp_w: float = get_viewport().get_visible_rect().size.x
	var pad := int(clamp(vp_w * 0.09, 32.0, 150.0))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 90)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	_who = Label.new()
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_who)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_body.custom_minimum_size = Vector2(0, 150)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_body)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -66
	_hint.offset_bottom = -26
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_override("font", StoryDB.FONT_TERMINUS)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.62, 0.62, 0.66))
	_hint.text = "tap to continue"
	_hint.modulate.a = 0.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)

	_apply_mode()

func _apply_mode() -> void:
	if _bg == null: return
	if _mode == "scrim":
		_bg.color = Color(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, SCRIM_ALPHA)
	else:
		_bg.color = BG_COLOR

func _show_block(i: int) -> void:
	if i < 0 or i >= _blocks.size(): return
	_index = i
	var b: Dictionary = _blocks[i]
	var v: Dictionary = StoryDB.voice(String(b.get("who", "narrator")))

	var txt := String(b.get("text", ""))
	if bool(v.get("upper", false)): txt = txt.to_upper()
	if bool(v.get("lower", false)): txt = txt.to_lower()
	txt = String(v.get("prefix", "")) + txt + String(v.get("suffix", ""))

	var col: Color = v.get("color", Color.WHITE)
	var font: Font = v.get("font", StoryDB.FONT_TERMINUS)

	_who.text = String(v.get("name", ""))
	_who.visible = _who.text != ""
	_who.add_theme_font_override("font", font)
	_who.add_theme_font_size_override("font_size", 15)
	_who.add_theme_color_override("font_color", Color(col, 0.5))

	_body.add_theme_font_override("normal_font", font)
	_body.add_theme_font_size_override("normal_font_size", int(v.get("size", 30)))
	_body.add_theme_color_override("default_color", col)
	_body.text = "[center]%s%s%s[/center]" % [
		String(v.get("fx_open", "")), txt, String(v.get("fx_close", "")),
	]

	_total = _body.get_total_character_count()
	if _total <= 0:
		# Shaping hasn't run yet this frame; fall back to the raw length so the
		# typewriter never collapses into an instant reveal.
		_total = txt.length()
	_shown = 0
	_body.visible_characters = 0
	_char_time = float(v.get("speed", 0.032))
	_tick_db = float(v.get("tick_db", -10.0))
	_accum = 0.0
	_typing = true

	if _hint_tw:
		_hint_tw.kill()
		_hint_tw = null
	_hint.modulate.a = 0.0

	if bool(v.get("glitch", false)):
		_glitch_flourish()

func _glitch_flourish() -> void:
	if Global.is_unlocked("chromatic_aberration") and ScreenFX.has_method("kick_chromatic"):
		ScreenFX.kick_chromatic(0.035, 0.35)
	AudioManager.play("glitch_sfx", -7.0, 0.02)
	var flash := Color(0.18, 0.04, 0.28)
	if _mode == "scrim":
		flash.a = SCRIM_ALPHA
	var base := _bg.color
	_bg.color = flash
	var tw := create_tween()
	tw.tween_property(_bg, "color", base, 0.45)

func _process(delta: float) -> void:
	if not _typing: return
	_accum += delta
	while _accum >= _char_time and _shown < _total:
		_accum -= _char_time
		_shown += 1
		_body.visible_characters = _shown
		if _shown % 2 == 0:
			AudioManager.play("tick", _tick_db, 0.06)
	if _shown >= _total:
		_end_typing()

func _end_typing() -> void:
	_typing = false
	_body.visible_characters = -1
	if _hint_tw:
		_hint_tw.kill()
	_hint_tw = create_tween().set_loops()
	_hint_tw.tween_property(_hint, "modulate:a", 0.85, 0.7)
	_hint_tw.tween_property(_hint, "modulate:a", 0.30, 0.7)

func _input(event: InputEvent) -> void:
	if _closing: return
	# A cut still waiting its turn is invisible and must be deaf too, or it would
	# eat the taps meant for the cut that is actually on screen.
	if not _started: return
	# The cut is modal: nothing behind it may react while it is up.
	get_viewport().set_input_as_handled()

	var is_tap := false
	if event is InputEventScreenTouch and event.pressed:
		is_tap = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_tap = true
	elif event is InputEventKey and event.pressed and not event.echo:
		is_tap = true
	if not is_tap:
		return
	# One action per frame — touch and emulated mouse both fire for one tap.
	var frame := Engine.get_process_frames()
	if frame == _last_input_frame:
		return
	_last_input_frame = frame

	if _typing:
		_shown = _total
		_body.visible_characters = -1
		_end_typing()
	elif _index + 1 < _blocks.size():
		AudioManager.play("ui_click", -12.0, 0.05)
		_show_block(_index + 1)
	else:
		_close()

func _close() -> void:
	if _closing: return
	_closing = true
	if _hint_tw:
		_hint_tw.kill()
		_hint_tw = null
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.22)
	tw.tween_callback(func():
		if is_inside_tree():
			get_tree().paused = _prev_paused
		# Order matters. Un-pause first so whoever is next records the real pre-cut
		# value. Emit before releasing so a listener that starts its own cut from
		# `finished` lands in the queue behind us and gets promoted by the _release
		# below, rather than opening on top of a cut that was already waiting.
		finished.emit()
		_release()
		queue_free()
	)
