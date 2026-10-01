extends CanvasLayer

@onready var title_label: Label = $Root/TitleBox/Title
@onready var subtitle_label: Label = $Root/TitleBox/Subtitle
@onready var tokens_label: Label = $Root/TopBar/TokensLabel
@onready var best_label: Label = $Root/TopBar/BestLabel
@onready var play_btn: Button = $Root/ButtonsScroll/ButtonsCenter/ButtonsPad/Buttons/PlayButton
@onready var shop_btn: Button = $Root/ButtonsScroll/ButtonsCenter/ButtonsPad/Buttons/ShopButton
@onready var settings_btn: Button = $Root/ButtonsScroll/ButtonsCenter/ButtonsPad/Buttons/SettingsButton
@onready var exit_btn: Button = $Root/ButtonsScroll/ButtonsCenter/ButtonsPad/Buttons/ExitButton

var _library_btn: Button = null
var _stats_btn: Button = null
var _daily_btn: Button = null
var _leaderboard_btn: Button = null
var _store_btn: Button = null
var _bg_offset: float = 0.0
## Referenced by path, not the global "ConfirmPopup" class name — that name
## is only registered once the editor rescans the project for class_name
## declarations, which a freshly-added script may not have gone through yet.
const ConfirmPopupScript := preload("res://confirm_popup.gd")

## Open "really quit?" confirmation, if one is currently up. Guards back-input
## and the exit buttons from acting twice while it's on screen.
var _quit_popup: CanvasLayer = null


func _ready() -> void:
	layer = 95
	play_btn.pressed.connect(_on_play)
	shop_btn.pressed.connect(_on_shop)
	settings_btn.pressed.connect(_on_settings)
	exit_btn.pressed.connect(_on_exit)

	var buttons = $Root/ButtonsScroll/ButtonsCenter/ButtonsPad/Buttons

	# Daily level — inserted at the very top when unlocked.
	if Global.is_unlocked("daily_level"):
		_daily_btn = Button.new()
		_daily_btn.text = "☀ Daily Level"
		_daily_btn.custom_minimum_size = Vector2(360, 64)
		_daily_btn.pressed.connect(_on_daily)
		buttons.add_child(_daily_btn)
		buttons.move_child(_daily_btn, 1)

	# Level Library button — inserted before Settings when library is unlocked.
	if Global.is_unlocked("level_library"):
		_library_btn = Button.new()
		_library_btn.text = "Level Library"
		_library_btn.custom_minimum_size = Vector2(360, 64)
		_library_btn.pressed.connect(_on_library)
		buttons.add_child(_library_btn)
		buttons.move_child(_library_btn, 2)

	# Stats — inserted before Settings when unlocked.
	if Global.is_unlocked("stats_menu"):
		_stats_btn = Button.new()
		_stats_btn.text = "Stats"
		_stats_btn.custom_minimum_size = Vector2(360, 64)
		_stats_btn.pressed.connect(_on_stats)
		buttons.add_child(_stats_btn)
		buttons.move_child(_stats_btn, buttons.get_child_count() - 3)

	# Leaderboard — inserted right after Stats (or before Settings if no Stats).
	if Global.is_unlocked("leaderboard"):
		_leaderboard_btn = Button.new()
		_leaderboard_btn.text = "Leaderboard"
		_leaderboard_btn.custom_minimum_size = Vector2(360, 64)
		_leaderboard_btn.pressed.connect(_on_leaderboard)
		buttons.add_child(_leaderboard_btn)
		# Insert directly after Stats button if present, otherwise after Library, otherwise after Shop
		if _stats_btn:
			buttons.move_child(_leaderboard_btn, _stats_btn.get_index() + 1)
		elif _library_btn:
			buttons.move_child(_leaderboard_btn, _library_btn.get_index() + 1)
		else:
			# After Shop (index 1), before Settings
			buttons.move_child(_leaderboard_btn, 2)

	# Always promote Settings + Exit to the top bar as compact icon buttons.
	# This keeps the main VBox short enough to fit at 720p regardless of how
	# many feature buttons have been unlocked.
	_promote_to_topbar()

	# If 5 or more buttons remain in the VBox, shrink them so they all fit.
	# (Settings/Exit are hidden — not counted — since _promote_to_topbar moved
	# them to the top bar already.)
	var visible_btns := _visible_button_count(buttons)
	if visible_btns >= 5:
		for b in buttons.get_children():
			if b is Button and b.visible:
				b.custom_minimum_size = Vector2(380, 56)
				b.add_theme_font_size_override("font_size", 24)
		buttons.add_theme_constant_override("separation", 10)

	_refresh_labels()
	UITheme.apply_current(self)
	# Built after the theme pass: it carries its own store styling and must not
	# turn grey on the placeholder theme.
	_build_store_button()

	if Global.is_unlocked("main_menu_extras"):
		_play_title_intro_tween()

	if Global.is_unlocked("home_polish"):
		_apply_home_polish()

	for b in [play_btn, shop_btn, settings_btn, exit_btn]:
		b.focus_mode = Control.FOCUS_ALL

	AudioManager.play_music("main_menu", 1.5)
	AudioManager.connect_ui_clicks(self)

	# Forced guide: congrats cut, then points the finger at Shop. No-ops after.
	Onboarding.attach.call_deferred(self, "main_menu")
	# Deferred after attach so the guide claims the screen first — StoryDB.pending()
	# suppresses ambient cuts while Onboarding.is_active().
	_play_pending_cut.call_deferred("menu_open")


## Fire any ambient StoryDB scene queued for this screen.
func _play_pending_cut(at: String) -> void:
	var scene: Dictionary = StoryDB.pending(at)
	if scene.is_empty(): return
	var cut = preload("res://story_cut.gd").new()
	get_tree().root.add_child(cut)
	cut.play(scene.get("blocks", []), String(scene.get("mode", "black")))
	StoryDB.mark_seen(scene)


func _refresh_labels() -> void:
	title_label.text = "Minimum Viable Platformer"
	subtitle_label.text = ""
	tokens_label.text = "★  %d  tokens" % Global.tokens
	best_label.text = "best:  %d m" % Global.best_distance


func _promote_to_topbar() -> void:
	# Replace the big Settings row with a proper cog icon-button in the top bar,
	# and Exit with a × icon. Frees up ~130 px in the button stack.
	var topbar := $Root/TopBar

	var gear := Button.new()
	gear.tooltip_text = "Settings"
	gear.custom_minimum_size = Vector2(64, 64)
	gear.flat = true
	gear.pressed.connect(_on_settings)
	topbar.add_child(gear)
	# Overlay a drawn cog polygon so the icon scales cleanly and doesn't rely
	# on emoji font rendering.
	var cog := Control.new()
	cog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cog.set_script(preload("res://cog_icon.gd"))
	# On the primitive (placeholder) menu the top bar is dark, so render the cog
	# in a light colour and keep it still — the spin/dark-ink styling is reserved
	# for the polished theme.
	if UITheme.current_theme_name() != "polished":
		cog.color = Color(0.90, 0.90, 0.92)
		cog.hub_color = Color(0.30, 0.30, 0.34)
		cog.accent_color = Color(0.70, 0.70, 0.74)
		cog.slowly_spin = false
	gear.add_child(cog)

	var quit_btn := Button.new()
	quit_btn.text = "✕"
	quit_btn.tooltip_text = "Quit"
	quit_btn.custom_minimum_size = Vector2(64, 64)
	quit_btn.add_theme_font_size_override("font_size", 34)
	quit_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	quit_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	quit_btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.8, 0.8))
	var quit_normal := StyleBoxFlat.new()
	quit_normal.bg_color = Color(0.55, 0.08, 0.08)
	quit_normal.corner_radius_top_left = 8
	quit_normal.corner_radius_top_right = 8
	quit_normal.corner_radius_bottom_left = 8
	quit_normal.corner_radius_bottom_right = 8
	var quit_hover := StyleBoxFlat.new()
	quit_hover.bg_color = Color(0.75, 0.12, 0.12)
	quit_hover.corner_radius_top_left = 8
	quit_hover.corner_radius_top_right = 8
	quit_hover.corner_radius_bottom_left = 8
	quit_hover.corner_radius_bottom_right = 8
	var quit_pressed := StyleBoxFlat.new()
	quit_pressed.bg_color = Color(0.40, 0.05, 0.05)
	quit_pressed.corner_radius_top_left = 8
	quit_pressed.corner_radius_top_right = 8
	quit_pressed.corner_radius_bottom_left = 8
	quit_pressed.corner_radius_bottom_right = 8
	quit_btn.add_theme_stylebox_override("normal", quit_normal)
	quit_btn.add_theme_stylebox_override("hover", quit_hover)
	quit_btn.add_theme_stylebox_override("pressed", quit_pressed)
	quit_btn.pressed.connect(_on_exit)
	topbar.add_child(quit_btn)

	settings_btn.visible = false
	exit_btn.visible = false

## "Get Tokens" — the in-app store entry, pinned bottom-left. Out of the way of
## the main button stack but always the same place, in the store's own pumpkin
## colours so it reads as a different kind of button from Play / Shop.
func _build_store_button() -> void:
	# Web / desktop release builds can never sell anything — no dead button there.
	if not (IAP.available or OS.is_debug_build()): return
	var btn := Button.new()
	btn.text = "Get Tokens"
	btn.custom_minimum_size = Vector2(0, 64)
	btn.add_theme_font_size_override("font_size", 24)
	btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	btn.offset_left = 24
	btn.offset_bottom = -24
	btn.offset_top = -88
	var ink := Color(0.18, 0.14, 0.10)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(1.00, 0.74, 0.32), "hover": Color(1.00, 0.80, 0.42),
			"pressed": Color(0.95, 0.55, 0.20), "focus": Color(1.00, 0.74, 0.32)}[state]
		sb.border_color = ink
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(32)
		sb.shadow_color = Color(0, 0, 0, 0.28)
		sb.shadow_size = 2 if state == "pressed" else 6
		sb.shadow_offset = Vector2(0, 3)
		sb.content_margin_left = 64   # room for the star badge
		sb.content_margin_right = 26
		btn.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(c, ink)
	var star := preload("res://stat_icon.gd").new()
	star.kind = 0  # STAR
	star.color = ink
	star.accent = Color(1.00, 0.95, 0.70)
	star.position = Vector2(14, 10)
	star.size = Vector2(44, 44)
	btn.add_child(star)
	btn.pressed.connect(func(): StoreView.open(self))
	$Root.add_child(btn)
	_store_btn = btn
	AudioManager.connect_ui_clicks(btn)
	_idle_nudge_store_button()


## A small hop every few seconds so the store is noticed without shouting.
## Skipped while a guide owns the screen.
func _idle_nudge_store_button() -> void:
	var tw := create_tween().set_loops()
	tw.tween_interval(5.0)
	tw.tween_callback(func():
		if _store_btn == null or Onboarding.suppresses_juice(): return
		_store_btn.pivot_offset = _store_btn.size * 0.5
		var hop := create_tween()
		hop.tween_property(_store_btn, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_BACK)
		hop.tween_property(_store_btn, "rotation", -0.05, 0.08)
		hop.tween_property(_store_btn, "rotation", 0.05, 0.08)
		hop.tween_property(_store_btn, "rotation", 0.0, 0.08)
		hop.parallel().tween_property(_store_btn, "scale", Vector2.ONE, 0.16))


func _apply_home_polish() -> void:
	title_label.add_theme_font_size_override("font_size", 68)
	title_label.add_theme_color_override("font_color", Color(1.00, 0.76, 0.35))
	title_label.add_theme_color_override("font_outline_color", Color(0.18, 0.14, 0.10))
	title_label.add_theme_constant_override("outline_size", 10)
	subtitle_label.add_theme_font_size_override("font_size", 22)
	subtitle_label.add_theme_color_override("font_color", Color(0.99, 0.88, 0.74))

	# Gentle looping bob on the title.
	var tw := create_tween().set_loops()
	tw.tween_property(title_label, "position:y", title_label.position.y + 6.0, 1.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(title_label, "position:y", title_label.position.y, 1.4).set_trans(Tween.TRANS_SINE)

	# Beefier buttons — bigger, more space, but only if we have room.
	# With 5+ buttons we already compacted them in _ready; don't re-expand.
	var btn_container := $Root/ButtonsScroll/ButtonsCenter/ButtonsPad/Buttons
	var btn_count := _visible_button_count(btn_container)
	if btn_count < 5:
		for b in btn_container.get_children():
			if b is Button and b.visible:
				b.custom_minimum_size = Vector2(420, 72)
				b.add_theme_font_size_override("font_size", 30)
		btn_container.add_theme_constant_override("separation", 18)
	else:
		for b in btn_container.get_children():
			if b is Button and b.visible:
				b.custom_minimum_size = Vector2(390, 56)
				b.add_theme_font_size_override("font_size", 24)
		btn_container.add_theme_constant_override("separation", 8)


## Counts only the Button children actually taking up space in the VBox —
## Settings/Exit stay real children after _promote_to_topbar hides them, so a
## raw get_child_count() overcounts and throws off the fit-shrinking above.
func _visible_button_count(container: VBoxContainer) -> int:
	var n := 0
	for b in container.get_children():
		if b is Button and b.visible:
			n += 1
	return n


func _play_title_intro_tween() -> void:
	title_label.modulate.a = 0.0
	title_label.scale = Vector2(0.6, 0.6)
	title_label.pivot_offset = title_label.size * 0.5
	var tw = create_tween()
	tw.tween_property(title_label, "modulate:a", 1.0, 0.45)
	tw.parallel().tween_property(title_label, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if Global.is_unlocked("main_menu_extras"):
		_bg_offset += delta * 12.0
		$Root.queue_redraw()


func _draw() -> void:
	pass


func _on_shop() -> void:
	get_tree().change_scene_to_file("res://shop.tscn")


func _on_settings() -> void:
	get_tree().change_scene_to_file("res://settings.tscn")


func _on_library() -> void:
	get_tree().change_scene_to_file("res://level_library.tscn")


func _on_stats() -> void:
	get_tree().change_scene_to_file("res://stats_view.tscn")


func _on_leaderboard() -> void:
	get_tree().change_scene_to_file("res://leaderboard_view.tscn")


func _on_daily() -> void:
	var gen = load("res://level_generator.gd")
	if gen:
		gen.current_seed = _daily_seed()
	Global.is_daily_run = true
	get_tree().change_scene_to_file("res://leve.tscn")


func _on_play() -> void:
	Global.is_daily_run = false
	get_tree().change_scene_to_file("res://leve.tscn")


func _daily_seed() -> int:
	var d: Dictionary = Time.get_date_dict_from_system()
	# Combine YYYYMMDD into a deterministic seed then clamp to 4-char code range.
	var raw := int(d.year) * 10000 + int(d.month) * 100 + int(d.day)
	return raw % 923521


func _on_exit() -> void:
	if _quit_popup: return
	_quit_popup = ConfirmPopupScript.ask_to_quit(self, "You'll close the game completely.")
	_quit_popup.tree_exited.connect(func(): _quit_popup = null)

func _input(event: InputEvent) -> void:
	if _quit_popup: return
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		var vp := get_viewport()
		if vp: vp.set_input_as_handled()
		_on_exit()
