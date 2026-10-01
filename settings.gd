extends CanvasLayer

@onready var back_btn: Button = $Root/TopBar/BackButton
@onready var title_label: Label = $Root/TopBar/Title

@onready var master_slider: HSlider = $Root/Panel/Scroll/V/MasterRow/Slider
@onready var sfx_slider: HSlider = $Root/Panel/Scroll/V/SFXRow/Slider
@onready var theme_option: OptionButton = $Root/Panel/Scroll/V/ThemeRow/Option
@onready var debug_cb: CheckBox = $Root/Panel/Scroll/V/DebugRow/CheckBox
@onready var primitives_cb: CheckBox = $Root/Panel/Scroll/V/PrimitivesRow/CheckBox
@onready var unlock_all_cb: CheckBox = $Root/Panel/Scroll/V/UnlockAllRow/CheckBox
@onready var reset_btn: Button = $Root/Panel/Scroll/V/ResetButton

## Restore Purchases button — kept around so its label can double as status text.
var _restore_btn: Button = null

func _ready() -> void:
	layer = 95
	back_btn.pressed.connect(_on_back)

	master_slider.value = Global.settings_cfg.get("master_volume", 0.8)
	sfx_slider.value = Global.settings_cfg.get("sfx_volume", 0.8)
	master_slider.value_changed.connect(func(v):
		Global.settings_cfg["master_volume"] = v
		Global.save_state()
		_apply_audio()
	)
	sfx_slider.value_changed.connect(func(v):
		Global.settings_cfg["sfx_volume"] = v
		Global.save_state()
		_apply_audio()
	)

	theme_option.add_item("Placeholder", 0)
	theme_option.add_item("Polished", 1)
	var cur := String(Global.settings_cfg.get("theme", "polished"))
	theme_option.selected = 1 if cur == "polished" else 0
	if not Global.is_unlocked("ui_polished"):
		theme_option.set_item_disabled(1, true)
		theme_option.selected = 0
	theme_option.item_selected.connect(func(i):
		Global.settings_cfg["theme"] = "polished" if i == 1 else "placeholder"
		Global.save_state()
		UITheme.apply_current(self)
	)

	debug_cb.button_pressed = Global.debug_toggles.get("show_overlay", true)
	debug_cb.toggled.connect(func(p):
		AudioManager.play("switch_on" if p else "switch_off", 0.0, 0.04)
		Global.debug_toggles["show_overlay"] = p
	)

	primitives_cb.button_pressed = Global.use_primitives
	primitives_cb.toggled.connect(func(p):
		AudioManager.play("switch_on" if p else "switch_off", 0.0, 0.04)
		Global.use_primitives = p
	)

	unlock_all_cb.button_pressed = Global.debug_toggles.get("unlock_all", false)
	unlock_all_cb.toggled.connect(func(p):
		AudioManager.play("switch_on" if p else "switch_off", 0.0, 0.04)
		Global.debug_toggles["unlock_all"] = p
	)

	reset_btn.pressed.connect(func():
		Global.reset_progress()
		title_label.text = "Settings (progress reset)"
	)
	title_label.text = "Settings"

	# Developer switches. "Unlock all" in a shipped build would hand out the
	# whole skill tree (and make the token store pointless), so release builds
	# never show these rows and never honour the toggle.
	if not OS.is_debug_build():
		$Root/Panel/Scroll/V/DebugRow.visible = false
		$Root/Panel/Scroll/V/UnlockAllRow.visible = false
		Global.debug_toggles["unlock_all"] = false

	# Clip hover highlights to the scroll area so they don't bleed outside the panel.
	$Root/Panel.clip_contents = true
	$Root/Panel/Scroll.clip_contents = true

	# ── Dynamic extra rows (added programmatically so the .tscn stays minimal) ──
	var vbox: VBoxContainer = $Root/Panel/Scroll/V
	_add_checkbox_row(vbox, "Blood trail",
		Global.settings_cfg.get("blood_trail", true),
		func(v: bool):
			Global.settings_cfg["blood_trail"] = v
			Global.save_state()
	)
	# Dev toggle: swaps the player to a crunchier, less-floaty jump curve.
	if OS.is_debug_build():
		_add_checkbox_row(vbox, "Use new jump",
			Global.settings_cfg.get("use_new_jump", false),
			func(v: bool):
				Global.settings_cfg["use_new_jump"] = v
				Global.save_state()
		)
	if Global.is_unlocked("palette_switcher"):
		_add_option_row(vbox, "Colour palette",
			["Default", "Warm", "Cool", "Night", "Neon"],
			["default", "warm", "cool", "night", "neon"],
			Global.color_palette,
			func(key: String):
				Global.color_palette = key
				Global.save_state()
		)
	if Global.is_unlocked("sky_color"):
		_add_option_row(vbox, "Sky colour",
			["Default", "Sunset", "Night", "Dawn", "Overcast"],
			["default", "sunset", "night", "dawn", "overcast"],
			Global.sky_color,
			func(key: String):
				Global.sky_color = key
				Global.save_state()
		)
	if Global.is_unlocked("fast_mode"):
		_add_checkbox_row(vbox, "Fast Mode (+points)",
			bool(Global.settings_cfg.get("fast_mode", false)),
			func(v: bool):
				Global.settings_cfg["fast_mode"] = v
				Global.save_state()
		)
	if Global.is_unlocked("font_select"):
		var font_files := _list_fonts()
		var names := []
		var keys := []
		names.append("Default")
		keys.append("default")
		for path in font_files:
			names.append(path.get_file().get_basename())
			keys.append(path.get_file())
		_add_option_row(vbox, "Font",
			names, keys,
			String(Global.settings_cfg.get("font_choice", "default")),
			func(key: String):
				Global.settings_cfg["font_choice"] = key
				Global.save_state()
				UITheme.apply_current(self)
		)
	
	if Global.is_unlocked("player_name"):
		_add_name_edit_row(vbox)

	if Global.is_unlocked("debug_mode"):
		_add_checkbox_row(vbox, "Show colliders",
			bool(Global.settings_cfg.get("show_collisions", false)),
			func(v: bool) -> void:
				Global.settings_cfg["show_collisions"] = v
				Global.debug_toggles["show_collisions"] = v
				Global.save_state()
				_apply_collisions()
		)

	_add_purchase_rows(vbox)

	UITheme.apply_current(self)
	_apply_audio()
	AudioManager.connect_ui_clicks(self)

## Restore Purchases and Manage Subscription. Both stores require these to be
## reachable from inside the app, so they are always built — the handlers report
## "unavailable" rather than the rows silently vanishing on a storeless build.
func _add_purchase_rows(parent: VBoxContainer) -> void:
	var tip_btn := _add_button_row(parent, "Support", "Support Developer ($0.50)")
	tip_btn.pressed.connect(func():
		if not IAP.available:
			tip_btn.text = "Store unavailable"
			await get_tree().create_timer(2.0).timeout
			if is_instance_valid(tip_btn): tip_btn.text = "Support Developer ($0.50)"
			return
		IAP.purchase(IAP.PRODUCT_DEV_SUPPORT)
	)
	_restore_btn = _add_button_row(parent, "Purchases", "Restore Purchases")
	_restore_btn.pressed.connect(_on_restore)
	var manage_btn := _add_button_row(parent, "Subscription", "Manage Subscription")
	manage_btn.pressed.connect(func(): IAP.manage_subscriptions())

func _on_restore() -> void:
	if not IAP.available:
		_restore_btn.text = "Store unavailable"
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(_restore_btn): _restore_btn.text = "Restore Purchases"
		return
	_restore_btn.disabled = true
	_restore_btn.text = "Restoring…"
	IAP.restore()
	var ok: bool = await IAP.restore_finished
	if not is_instance_valid(_restore_btn): return
	_restore_btn.disabled = false
	_restore_btn.text = "Restored" if ok else "Nothing to restore"
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(_restore_btn): _restore_btn.text = "Restore Purchases"

## Label + button, matching the label/control shape of the checkbox rows above.
func _add_button_row(parent: VBoxContainer, label_text: String, btn_text: String) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.text = label_text
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = btn_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 20)
	row.add_child(btn)
	parent.add_child(row)
	return btn

func _list_fonts() -> Array:
	return SkillsDB.list_font_files()

func _add_name_edit_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.text = "Profile Name"
	row.add_child(lbl)
	
	var edit_btn := Button.new()
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_btn.add_theme_font_size_override("font_size", 22)
	edit_btn.text = LeaderboardService.get_player_name()
	edit_btn.pressed.connect(func():
		var dialog_script = load("res://enter_name_dialog.gd")
		if dialog_script:
			var dialog = dialog_script.new()
			dialog.allow_cancel = true
			dialog.name_submitted.connect(func(new_name):
				edit_btn.text = new_name
			)
			add_child(dialog)
	)
	row.add_child(edit_btn)
	parent.add_child(row)

func _add_checkbox_row(parent: VBoxContainer, label_text: String, initial: bool, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.text = label_text
	row.add_child(lbl)
	var cb := CheckBox.new()
	cb.button_pressed = initial
	cb.toggled.connect(func(v: bool):
		AudioManager.play("switch_on" if v else "switch_off", 0.0, 0.04)
		callback.call(v)
	)
	row.add_child(cb)
	parent.add_child(row)

func _add_option_row(parent: VBoxContainer, label_text: String,
		display_names: Array, keys: Array, current_key: String, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.text = label_text
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in display_names.size():
		opt.add_item(display_names[i], i)
	var idx := keys.find(current_key)
	opt.selected = max(0, idx)
	opt.item_selected.connect(func(i: int): callback.call(keys[i]))
	row.add_child(opt)
	parent.add_child(row)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		_on_back()

func _apply_audio() -> void:
	var master_bus = AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		var v = float(Global.settings_cfg.get("master_volume", 0.8))
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(max(0.0001, v)))
	AudioManager.apply_volumes()

func _apply_collisions() -> void:
	get_tree().debug_collisions_hint = false #bool(Global.settings_cfg.get("show_collisions", false))

func _on_back() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")
