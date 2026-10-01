extends CanvasLayer

# Modal dialog to enter or edit the player's profile name.
# Can be shown on game boot, on game over, or from settings.

const FONT_KA1 := preload("res://assets/fonts/ka1.ttf")
const FONT_FUNK := preload("res://assets/fonts/funkymuskrat.ttf")

signal name_submitted(new_name: String)

@export var allow_cancel: bool = true

var _dim: ColorRect
var _panel: PanelContainer
var _line_edit: LineEdit
var _err_lbl: Label
var _cancel_btn: Button
var _save_btn: Button

func _ready() -> void:
	layer = 100
	_build_ui()
	
	# Pre-fill LineEdit
	var current_name := ""
	if Global.settings_cfg.has("player_name"):
		current_name = str(Global.settings_cfg["player_name"])
	_line_edit.text = current_name
	_line_edit.grab_focus()
	_line_edit.caret_column = current_name.length()
	
	# Apply visual theme
	UITheme.apply_current(self)
	
	# Extra custom LineEdit style to match the warm cream / ink outline aesthetic
	var is_polished = UITheme.current_theme_name() == "polished"
	var sb_le := StyleBoxFlat.new()
	if is_polished:
		sb_le.bg_color = Color(1.0, 1.0, 1.0, 0.95)
		sb_le.border_color = UITheme.COL_INK
		sb_le.set_border_width_all(3)
		sb_le.set_corner_radius_all(12)
		sb_le.content_margin_left = 16
		sb_le.content_margin_right = 16
		sb_le.content_margin_top = 10
		sb_le.content_margin_bottom = 10
		_line_edit.add_theme_color_override("font_color", UITheme.COL_INK)
		_line_edit.add_theme_color_override("caret_color", UITheme.COL_INK)
	else:
		sb_le.bg_color = Color(0.15, 0.15, 0.15)
		sb_le.border_color = Color(0.5, 0.5, 0.5)
		sb_le.set_border_width_all(2)
		sb_le.content_margin_left = 12
		sb_le.content_margin_right = 12
		sb_le.content_margin_top = 8
		sb_le.content_margin_bottom = 8
	
	_line_edit.add_theme_stylebox_override("normal", sb_le)
	_line_edit.add_theme_stylebox_override("focus", sb_le)
	
	# Cancel button configuration
	if not allow_cancel:
		# If cancel is not allowed (e.g. initial setup forcing name selection),
		# disable or hide the cancel button.
		_cancel_btn.visible = false
	
	# Animate panel popping up
	_play_intro_tween()

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, 0.65)
	root.add_child(_dim)
	
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(_panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	_panel.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "Player Profile"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_KA1)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.10, 0.06))
	title.add_theme_constant_override("outline_size", 6)
	vbox.add_child(title)
	
	# Prompt description
	var desc := Label.new()
	desc.text = "Choose a name to represent yourself on the global leaderboards."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 18)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc)
	
	# LineEdit input field
	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = "Enter your name..."
	_line_edit.max_length = 16
	_line_edit.add_theme_font_size_override("font_size", 22)
	_line_edit.text_submitted.connect(_on_text_submitted)
	vbox.add_child(_line_edit)
	
	# Error display label
	_err_lbl = Label.new()
	_err_lbl.text = ""
	_err_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_err_lbl.add_theme_font_size_override("font_size", 16)
	_err_lbl.add_theme_color_override("font_color", Color(0.85, 0.32, 0.32)) # sleek HSL red
	vbox.add_child(_err_lbl)
	
	# Button Row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.custom_minimum_size = Vector2(150, 48)
	_cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(_cancel_btn)
	
	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.custom_minimum_size = Vector2(150, 48)
	_save_btn.pressed.connect(_on_save)
	btn_row.add_child(_save_btn)

func _play_intro_tween() -> void:
	_panel.scale = Vector2(0.85, 0.85)
	_panel.pivot_offset = _panel.size * 0.5
	_panel.modulate.a = 0.0
	_dim.modulate.a = 0.0
	
	# Need a tiny delay for size calculations to populate pivot
	await get_tree().process_frame
	_panel.pivot_offset = _panel.size * 0.5
	
	var tw = create_tween()
	tw.tween_property(_dim, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(_panel, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_save() -> void:
	var new_name := _line_edit.text.strip_edges()
	
	# Validation
	if new_name.length() < 2:
		_show_error("Name is too short (min 2 chars)")
		return
	if new_name.length() > 16:
		_show_error("Name is too long (max 16 chars)")
		return
	
	# Regex validation to prevent weird characters
	var regex := RegEx.new()
	regex.compile("^[a-zA-Z0-9 _-]+$")
	var result := regex.search(new_name)
	if not result:
		_show_error("Name contains invalid characters")
		return
		
	var lower_name := new_name.to_lower()
	if lower_name == "anonymous" or lower_name == "player" or lower_name == "null":
		_show_error("Please choose a unique profile name")
		return

	# Claim the name globally so it's unique across all players. A taken name
	# gets a small counter suffix (Bob → Bob2). claim_unique_name persists the
	# resolved name into Global.settings_cfg itself.
	_set_busy(true)
	LeaderboardService.claim_unique_name(new_name, func(resolved: String, was_suffixed: bool):
		_set_busy(false)
		if was_suffixed:
			# Reflect the resolved name and let the player see why it changed.
			_line_edit.text = resolved
			_show_error("\"%s\" was taken — you're now \"%s\"" % [new_name, resolved])
			# Give them a beat to read it, then close.
			await get_tree().create_timer(1.4).timeout
		emit_signal("name_submitted", resolved)
		_close()
	)

func _set_busy(busy: bool) -> void:
	_save_btn.disabled = busy
	_line_edit.editable = not busy
	if _cancel_btn:
		_cancel_btn.disabled = busy
	_save_btn.text = "Checking…" if busy else "Save"

func _show_error(err_text: String) -> void:
	_err_lbl.text = err_text
	_panel.pivot_offset = _panel.size * 0.5
	
	# Small shake animation on error
	var original_x := _panel.position.x
	var tw = create_tween()
	tw.tween_property(_panel, "position:x", original_x - 8.0, 0.05)
	tw.tween_property(_panel, "position:x", original_x + 8.0, 0.05)
	tw.tween_property(_panel, "position:x", original_x - 6.0, 0.05)
	tw.tween_property(_panel, "position:x", original_x + 6.0, 0.05)
	tw.tween_property(_panel, "position:x", original_x, 0.05)

func _on_text_submitted(_text: String) -> void:
	_on_save()

func _on_cancel() -> void:
	_close()

func _close() -> void:
	var tw = create_tween()
	tw.tween_property(_panel, "scale", Vector2(0.85, 0.85), 0.18).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_panel, "modulate:a", 0.0, 0.18)
	tw.parallel().tween_property(_dim, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)
