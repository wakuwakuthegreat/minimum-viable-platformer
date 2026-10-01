extends CanvasLayer

## Stats screen — unlocked by the "stats_menu" skill. Reads from Global.stats.
## Redesigned: sectioned layout with headers, emoji, larger fonts, alternating rows.

func _ready() -> void:
	layer = 50
	_build_ui()
	UITheme.apply_current(self)

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.07, 0.05, 0.98)
	root.add_child(bg)

	# Subtle gradient overlay at the top for depth
	var grad_rect := ColorRect.new()
	grad_rect.set_anchors_preset(Control.PRESET_TOP_WIDE)
	grad_rect.offset_bottom = 200
	grad_rect.color = Color(0.18, 0.13, 0.08, 0.35)
	root.add_child(grad_rect)

	# ── Top bar ──────────────────────────────────────────────────────────────
	var topbar := HBoxContainer.new()
	topbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	topbar.custom_minimum_size = Vector2(0, 80)
	topbar.offset_left  = 28
	topbar.offset_right = -28
	topbar.add_theme_constant_override("separation", 16)
	root.add_child(topbar)

	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.custom_minimum_size = Vector2(130, 52)
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.pressed.connect(_on_back)
	topbar.add_child(back_btn)

	var title := Label.new()
	title.text = "📊  Stats"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.00, 0.80, 0.35))
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.10, 0.05))
	title.add_theme_constant_override("outline_size", 6)
	topbar.add_child(title)

	# Spacer to balance the back button
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(130, 0)
	topbar.add_child(spacer)

	# ── Scroll area ──────────────────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top    = 92
	scroll.offset_left   = 24
	scroll.offset_right  = -24
	scroll.offset_bottom = -16
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	var s: Dictionary = Global.stats

	# ── Section: Runs ────────────────────────────────────────────────────────
	_add_section_header(vbox, "🏃  Runs")
	var row_idx := 0
	_add_stat_row(vbox, "Playtime",          _fmt_time(float(s.get("playtime_sec", 0.0))),     "⏱", row_idx); row_idx += 1
	_add_stat_row(vbox, "Sessions",          str(int(s.get("sessions", 0))),                   "📅", row_idx); row_idx += 1
	_add_stat_row(vbox, "Days played",       str(int((s.get("days_played", {}) as Dictionary).size())), "🗓", row_idx); row_idx += 1
	_add_stat_row(vbox, "Total distance",    "%d m" % int(s.get("total_distance_m", 0)),       "📏", row_idx); row_idx += 1
	_add_stat_row(vbox, "Longest run",       "%d m" % int(s.get("longest_run_m", 0)),          "🏆", row_idx); row_idx += 1
	_add_stat_row(vbox, "Seeds visited",     str(int((s.get("seeds_visited", {}) as Dictionary).size())), "🌱", row_idx); row_idx += 1
	_add_stat_row(vbox, "Daily levels done", str(int(s.get("daily_completed", 0))),            "☀", row_idx); row_idx += 1

	# ── Section: Movement ────────────────────────────────────────────────────
	_add_section_spacer(vbox)
	_add_section_header(vbox, "🦘  Movement")
	row_idx = 0
	_add_stat_row(vbox, "Jumps",             str(int(s.get("jumps", 0))),                      "↑", row_idx); row_idx += 1
	_add_stat_row(vbox, "Highest jump",      "%d px" % int(s.get("highest_jump_px", 0)),       "📐", row_idx); row_idx += 1

	# ── Section: Combat ──────────────────────────────────────────────────────
	_add_section_spacer(vbox)
	_add_section_header(vbox, "⚔️  Combat")
	row_idx = 0
	_add_stat_row(vbox, "Enemies stomped",   str(int(s.get("enemies_stomped", 0))),            "👟", row_idx); row_idx += 1
	_add_stat_row(vbox, "Bullets fired",     str(int(s.get("bullets_fired", 0))),              "💥", row_idx); row_idx += 1
	_add_stat_row(vbox, "Longest combo",     str(int(s.get("longest_combo", 0))),              "🔥", row_idx); row_idx += 1
	_add_stat_row(vbox, "Deaths",            str(int(s.get("deaths", 0))),                     "💀", row_idx); row_idx += 1

	# ── Section: Economy ─────────────────────────────────────────────────────
	_add_section_spacer(vbox)
	_add_section_header(vbox, "💰  Economy")
	row_idx = 0
	_add_stat_row(vbox, "Points earned",     str(int(s.get("total_points_earned", 0))),        "⭐", row_idx); row_idx += 1
	_add_stat_row(vbox, "Points spent",      str(int(s.get("total_points_spent", 0))),         "🛒", row_idx); row_idx += 1
	_add_stat_row(vbox, "Upgrades bought",   str(int(s.get("upgrades_bought", 0))),            "🔧", row_idx); row_idx += 1

	# ── Section: Deaths by Cause ─────────────────────────────────────────────
	var causes: Dictionary = s.get("deaths_by_cause", {})
	if not causes.is_empty():
		_add_section_spacer(vbox)
		_add_section_header(vbox, "💀  Deaths by Cause")
		var keys: Array = causes.keys()
		keys.sort_custom(func(a, b): return int(causes[a]) > int(causes[b]))
		row_idx = 0
		for k in keys:
			_add_stat_row(vbox, str(k).capitalize(), str(int(causes[k])), "•", row_idx)
			row_idx += 1

	# Bottom padding
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(pad)

func _add_section_header(vbox: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(1.00, 0.74, 0.32))
	lbl.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04))
	lbl.add_theme_constant_override("outline_size", 4)
	# Underline-like separator after header
	var sep_container := VBoxContainer.new()
	sep_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(lbl)
	var line := ColorRect.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size = Vector2(0, 2)
	line.color = Color(1.00, 0.74, 0.32, 0.35)
	vbox.add_child(line)

func _add_section_spacer(vbox: VBoxContainer) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 18)
	vbox.add_child(sp)

func _add_stat_row(vbox: VBoxContainer, label_text: String, value_text: String, icon: String, row_index: int) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Alternating row tints
	var sb := StyleBoxFlat.new()
	if row_index % 2 == 0:
		sb.bg_color = Color(0.14, 0.12, 0.09, 0.55)
	else:
		sb.bg_color = Color(0.10, 0.08, 0.06, 0.25)
	sb.set_corner_radius_all(6)
	sb.content_margin_left   = 16
	sb.content_margin_right  = 16
	sb.content_margin_top    = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	vbox.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	panel.add_child(hbox)

	# Icon
	var icon_lbl := Label.new()
	icon_lbl.text = icon
	icon_lbl.add_theme_font_size_override("font_size", 26)
	icon_lbl.custom_minimum_size = Vector2(36, 0)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(icon_lbl)

	# Label
	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(0.90, 0.84, 0.76))
	hbox.add_child(l)

	# Value — larger, highlighted
	var v := Label.new()
	v.text = value_text
	v.add_theme_font_size_override("font_size", 28)
	v.add_theme_color_override("font_color", Color(1.0, 0.95, 0.65))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.custom_minimum_size = Vector2(160, 0)
	hbox.add_child(v)

func _fmt_time(sec: float) -> String:
	var s := int(sec)
	var h := s / 3600
	var m := (s % 3600) / 60
	var ss := s % 60
	if h > 0:
		return "%dh %dm %ds" % [h, m, ss]
	return "%dm %ds" % [m, ss]

func _on_back() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		_on_back()
