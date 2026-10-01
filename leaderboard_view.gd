extends CanvasLayer

# Leaderboard screen showing level-specific stats and global Hall of Fame.
# Programmatic UI following minimum-viable-platformer's polished style.

const FONT_KA1 := preload("res://assets/fonts/ka1.ttf")

enum Tab { BEST_SCORE, LONGEST_DISTANCE, HIGHEST_COMBO, MOST_PLAYED, GLOBAL_HOF }

var target_seed: String = ""
var current_tab: int = Tab.GLOBAL_HOF

var _vbox: VBoxContainer
var _tabs_hbox: HBoxContainer
var _title_lbl: Label
var _active_stylebox: StyleBoxFlat

func _ready() -> void:
	layer = 50
	
	# Load targeted seed from LeaderboardService convenience state
	target_seed = LeaderboardService.current_view_seed
	
	# Determine initial tab based on whether seed is provided
	if target_seed != "":
		current_tab = Tab.BEST_SCORE
	else:
		current_tab = Tab.GLOBAL_HOF
		
	_setup_active_stylebox()
	_build_ui()
	
	# Connect to LeaderboardService signals
	LeaderboardService.level_leaderboard_loaded.connect(_on_level_leaderboard_loaded)
	LeaderboardService.most_played_loaded.connect(_on_most_played_loaded)
	LeaderboardService.hall_of_fame_loaded.connect(_on_hall_of_fame_loaded)
	
	_load_active_tab()
	UITheme.apply_current(self)
	_refresh_tab_styling()

func _setup_active_stylebox() -> void:
	_active_stylebox = StyleBoxFlat.new()
	_active_stylebox.bg_color = UITheme.COL_GRASS
	_active_stylebox.border_color = UITheme.COL_INK
	_active_stylebox.set_border_width_all(3)
	_active_stylebox.set_corner_radius_all(18)
	_active_stylebox.content_margin_left = 20
	_active_stylebox.content_margin_right = 20
	_active_stylebox.content_margin_top = 10
	_active_stylebox.content_margin_bottom = 10

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.10, 0.08, 0.06, 0.97)
	root.add_child(bg)
	
	# Top bar
	var topbar := HBoxContainer.new()
	topbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	topbar.custom_minimum_size = Vector2(0, 72)
	topbar.add_theme_constant_override("separation", 24)
	topbar.offset_left = 24
	topbar.offset_right = -24
	root.add_child(topbar)
	
	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.custom_minimum_size = Vector2(120, 0)
	back_btn.pressed.connect(_on_back)
	topbar.add_child(back_btn)
	
	_title_lbl = Label.new()
	_update_title_text()
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_override("font", FONT_KA1)
	_title_lbl.add_theme_font_size_override("font_size", 38)
	_title_lbl.add_theme_color_override("font_color", Color(1.00, 0.74, 0.32))
	_title_lbl.add_theme_color_override("font_outline_color", Color(0.15, 0.10, 0.06))
	_title_lbl.add_theme_constant_override("outline_size", 8)
	topbar.add_child(_title_lbl)
	
	var refresh_btn := Button.new()
	refresh_btn.text = "↺ Refresh"
	refresh_btn.custom_minimum_size = Vector2(120, 0)
	refresh_btn.pressed.connect(_on_refresh)
	topbar.add_child(refresh_btn)
	
	# Tab button bar
	_tabs_hbox = HBoxContainer.new()
	_tabs_hbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tabs_hbox.offset_top = 80
	_tabs_hbox.offset_left = 32
	_tabs_hbox.offset_right = -32
	_tabs_hbox.custom_minimum_size = Vector2(0, 56)
	_tabs_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs_hbox.add_theme_constant_override("separation", 10)
	root.add_child(_tabs_hbox)
	
	_build_tab_buttons()
	
	# Content Scroll Area
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 150
	scroll.offset_left = 32
	scroll.offset_right = -32
	scroll.offset_bottom = -16
	root.add_child(scroll)
	
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_vbox)

func _update_title_text() -> void:
	if current_tab == Tab.GLOBAL_HOF:
		_title_lbl.text = "Global Hall of Fame"
	elif target_seed != "":
		_title_lbl.text = "Leaderboard: Seed %s" % target_seed
	else:
		_title_lbl.text = "Leaderboards"

func _build_tab_buttons() -> void:
	for c in _tabs_hbox.get_children():
		c.queue_free()
		
	# Tab details: [enum, label_text]
	var tabs_to_show := []
	if target_seed != "":
		tabs_to_show.append([Tab.BEST_SCORE, "Best Score"])
		tabs_to_show.append([Tab.LONGEST_DISTANCE, "Distance"])
		tabs_to_show.append([Tab.HIGHEST_COMBO, "Combo"])
		tabs_to_show.append([Tab.MOST_PLAYED, "Plays"])
	
	tabs_to_show.append([Tab.GLOBAL_HOF, "Global HOF"])
	
	for tab_info in tabs_to_show:
		var tab_id: int = tab_info[0]
		var tab_label: String = tab_info[1]
		
		var btn := Button.new()
		btn.text = tab_label
		btn.custom_minimum_size = Vector2(160, 48)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		btn.set_meta("tab_id", tab_id)
		_tabs_hbox.add_child(btn)

func _refresh_tab_styling() -> void:
	var is_polished = UITheme.current_theme_name() == "polished"
	for btn in _tabs_hbox.get_children():
		if btn is Button:
			var t_id = btn.get_meta("tab_id")
			if t_id == current_tab:
				if is_polished:
					btn.add_theme_stylebox_override("normal", _active_stylebox)
					btn.add_theme_stylebox_override("hover", _active_stylebox)
					btn.add_theme_stylebox_override("pressed", _active_stylebox)
					btn.add_theme_color_override("font_color", Color.WHITE)
				else:
					var sb = StyleBoxFlat.new()
					sb.bg_color = Color(0.4, 0.4, 0.4)
					btn.add_theme_stylebox_override("normal", sb)
			else:
				# Reset to default UITheme stylebox
				btn.remove_theme_stylebox_override("normal")
				btn.remove_theme_stylebox_override("hover")
				btn.remove_theme_stylebox_override("pressed")
				btn.remove_theme_color_override("font_color")

func _on_tab_pressed(tab_id: int) -> void:
	if current_tab == tab_id:
		return
	current_tab = tab_id
	_update_title_text()
	_refresh_tab_styling()
	_load_active_tab()

func _load_active_tab() -> void:
	# Clear list
	for c in _vbox.get_children():
		c.queue_free()
		
	var loading := Label.new()
	loading.text = "Fetching leaderboards..."
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_theme_font_size_override("font_size", 24)
	loading.name = "LoadingLabel"
	_vbox.add_child(loading)
	
	match current_tab:
		Tab.BEST_SCORE:
			LeaderboardService.get_level_leaderboard(target_seed, "best_score")
		Tab.LONGEST_DISTANCE:
			LeaderboardService.get_level_leaderboard(target_seed, "longest_distance")
		Tab.HIGHEST_COMBO:
			LeaderboardService.get_level_leaderboard(target_seed, "highest_combo")
		Tab.MOST_PLAYED:
			LeaderboardService.get_most_played_leaderboard(target_seed)
		Tab.GLOBAL_HOF:
			LeaderboardService.get_hall_of_fame()

# ─── SERVICE CALLBACKS ─────────────────────────────────────────────────────

func _on_level_leaderboard_loaded(res_seed: String, res_stat: String, results: Array, success: bool, error: String) -> void:
	# Check if this response belongs to our current state
	if res_seed != target_seed:
		return
	var expected_tab = -1
	match res_stat:
		"best_score": expected_tab = Tab.BEST_SCORE
		"longest_distance": expected_tab = Tab.LONGEST_DISTANCE
		"highest_combo": expected_tab = Tab.HIGHEST_COMBO
	
	if current_tab != expected_tab:
		return
		
	_display_stat_results(results, success, error, res_stat)

func _on_most_played_loaded(res_seed: String, results: Array, success: bool, error: String) -> void:
	if res_seed != target_seed or current_tab != Tab.MOST_PLAYED:
		return
	_display_play_results(results, success, error)

func _on_hall_of_fame_loaded(hall_of_fame: Dictionary, success: bool, error: String) -> void:
	if current_tab != Tab.GLOBAL_HOF:
		return
	_display_hof_results(hall_of_fame, success, error)

# ─── RESULT DISPLAY ────────────────────────────────────────────────────────

func _display_stat_results(results: Array, success: bool, error: String, stat: String) -> void:
	_clear_loading()
	if not success:
		_display_error(error)
		return
		
	if results.is_empty():
		_display_empty("No scores recorded for this stat yet.\nBe the first!")
		return
		
	var unit := ""
	match stat:
		"longest_distance": unit = " m"
		"highest_combo": unit = "x combo"
		
	var rank := 1
	var local_player_name := LeaderboardService.get_player_name().to_lower()
	
	for entry in results:
		if entry is Dictionary:
			var player_name: String = entry.get("player_name", "Anonymous")
			var val: int = int(entry.get("score", 0))
			
			var highlight := player_name.to_lower() == local_player_name and LeaderboardService.has_unique_name()
			_add_ranking_row(rank, player_name, str(val) + unit, highlight)
			rank += 1

func _display_play_results(results: Array, success: bool, error: String) -> void:
	_clear_loading()
	if not success:
		_display_error(error)
		return
		
	if results.is_empty():
		_display_empty("No runs recorded for this level yet.")
		return
		
	var rank := 1
	var local_player_name := LeaderboardService.get_player_name().to_lower()
	
	for entry in results:
		if entry is Dictionary:
			var player_name: String = entry.get("player_name", "Anonymous")
			var count: int = int(entry.get("count", 0))
			
			var highlight := player_name.to_lower() == local_player_name and LeaderboardService.has_unique_name()
			_add_ranking_row(rank, player_name, str(count) + " runs", highlight)
			rank += 1

func _display_hof_results(hof: Dictionary, success: bool, error: String) -> void:
	_clear_loading()
	if not success:
		_display_error(error)
		return

	if hof.is_empty() or (not hof.has("highest_combo") and not hof.has("longest_distance")):
		_display_empty("Global records are clean.\nGo set one!")
		return

	var local_player_name := LeaderboardService.get_player_name().to_lower()

	# Display Longest Distance Records (top 3)
	_add_hof_heading("🏆 Longest Distance — Top 3")
	var dist_arr := _hof_to_array(hof.get("longest_distance"))
	if dist_arr.is_empty():
		_add_hof_row("—", "None", "0 m", "", false)
	else:
		var rank := 1
		for rec in dist_arr:
			if not rec is Dictionary: continue
			var p_name: String = rec.get("player_name", "Anonymous")
			var val: int = int(rec.get("value", 0))
			var seed_id: String = rec.get("level_id", "")
			var highlight := p_name.to_lower() == local_player_name and LeaderboardService.has_unique_name()
			_add_hof_row("#" + str(rank), p_name, str(val) + " m", "Seed: " + seed_id, highlight)
			rank += 1

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	_vbox.add_child(spacer)

	# Display Highest Combo Records (top 3)
	_add_hof_heading("⚡ Highest Combo — Top 3")
	var combo_arr := _hof_to_array(hof.get("highest_combo"))
	if combo_arr.is_empty():
		_add_hof_row("—", "None", "0x", "", false)
	else:
		var rank := 1
		for rec in combo_arr:
			if not rec is Dictionary: continue
			var p_name: String = rec.get("player_name", "Anonymous")
			var val: int = int(rec.get("value", 0))
			var seed_id: String = rec.get("level_id", "")
			var highlight := p_name.to_lower() == local_player_name and LeaderboardService.has_unique_name()
			_add_hof_row("#" + str(rank), p_name, str(val) + "x combo", "Seed: " + seed_id, highlight)
			rank += 1

## Normalize a HOF stat field into an array of record dicts. Handles both the
## new top-3 array format and legacy single-record maps.
func _hof_to_array(raw) -> Array:
	if raw is Array:
		return raw
	if raw is Dictionary and raw.has("value"):
		return [raw]
	return []

func _clear_loading() -> void:
	var l = _vbox.get_node_or_null("LoadingLabel")
	if l:
		l.queue_free()

func _display_error(err_text: String) -> void:
	var lbl := Label.new()
	lbl.text = "Error: " + err_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.32, 0.32))
	_vbox.add_child(lbl)
	
	var retry := Button.new()
	retry.text = "Retry"
	retry.custom_minimum_size = Vector2(160, 48)
	retry.pressed.connect(_load_active_tab)
	_vbox.add_child(retry)
	UITheme.apply_current(retry)

func _display_empty(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(lbl)

func _add_ranking_row(rank: int, player_name: String, val_str: String, highlight: bool) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(panel)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	panel.add_child(hbox)
	
	# Rank
	var rank_lbl := Label.new()
	rank_lbl.text = "#" + str(rank)
	rank_lbl.custom_minimum_size = Vector2(60, 0)
	rank_lbl.add_theme_font_size_override("font_size", 20)
	hbox.add_child(rank_lbl)
	
	# Name
	var name_lbl := Label.new()
	name_lbl.text = player_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 20)
	hbox.add_child(name_lbl)
	
	# Value
	var val_lbl := Label.new()
	val_lbl.text = val_str
	val_lbl.add_theme_font_size_override("font_size", 20)
	hbox.add_child(val_lbl)
	
	# Highlights if it's the player
	if highlight:
		for lbl in [rank_lbl, name_lbl, val_lbl]:
			lbl.add_theme_color_override("font_color", UITheme.COL_GRASS_HI)
			
	UITheme.apply_current(panel)

func _add_hof_heading(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", FONT_KA1)
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", UITheme.COL_PUMPKIN_HI)
	lbl.add_theme_color_override("font_outline_color", UITheme.COL_INK)
	lbl.add_theme_constant_override("outline_size", 5)
	_vbox.add_child(lbl)

func _add_hof_row(rank_str: String, player_name: String, value_str: String, details_str: String, highlight: bool) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	panel.add_child(hbox)

	# Rank
	var rank_lbl := Label.new()
	rank_lbl.text = rank_str
	rank_lbl.custom_minimum_size = Vector2(48, 0)
	rank_lbl.add_theme_font_size_override("font_size", 22)
	hbox.add_child(rank_lbl)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(name_lbl)

	# Record value
	var val_lbl := Label.new()
	val_lbl.text = value_str
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.add_theme_font_size_override("font_size", 22)
	hbox.add_child(val_lbl)

	# Details (Seed code)
	var det_lbl := Label.new()
	det_lbl.text = details_str
	det_lbl.add_theme_font_size_override("font_size", 18)
	det_lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))
	hbox.add_child(det_lbl)

	if highlight:
		for lbl in [rank_lbl, name_lbl, val_lbl]:
			lbl.add_theme_color_override("font_color", UITheme.COL_GRASS_HI)

	UITheme.apply_current(panel)

func _on_back() -> void:
	# Clean up connections
	LeaderboardService.level_leaderboard_loaded.disconnect(_on_level_leaderboard_loaded)
	LeaderboardService.most_played_loaded.disconnect(_on_most_played_loaded)
	LeaderboardService.hall_of_fame_loaded.disconnect(_on_hall_of_fame_loaded)
	
	var was_seed = LeaderboardService.current_view_seed != ""
	LeaderboardService.current_view_seed = ""
	
	if was_seed:
		get_tree().change_scene_to_file("res://level_library.tscn")
	else:
		get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_refresh() -> void:
	print("[LeaderboardView] Manual refresh — clearing cache for current view")
	# Bust the cache for whatever is currently visible
	if target_seed != "":
		LeaderboardService._cache_invalidate_for_seed(target_seed)
	else:
		LeaderboardService._cache.erase(LeaderboardService.CACHE_KEY_HOF)
	_load_active_tab()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		_on_back()
