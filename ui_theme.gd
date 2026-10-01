extends Node
class_name UITheme

## Two themes: "placeholder" (drab default Godot grey) and "polished" (matches the
## hand-drawn warm cream / forest-green palette of the reference screenshot).
##
## Usage:
##   UITheme.apply(self, "polished")       # styles the root and every descendant
##   UITheme.apply_current(self)            # uses Global.settings_cfg.theme

const COL_PEACH      := Color(0.99, 0.86, 0.72)
const COL_PEACH_DARK := Color(0.92, 0.70, 0.50)
const COL_INK        := Color(0.18, 0.14, 0.10)
const COL_GRASS_HI   := Color(0.85, 0.92, 0.45)
const COL_GRASS      := Color(0.60, 0.78, 0.32)
const COL_GRASS_DARK := Color(0.36, 0.50, 0.20)
const COL_PUMPKIN    := Color(0.95, 0.55, 0.20)
const COL_PUMPKIN_HI := Color(1.00, 0.74, 0.32)

static func _placeholder_button() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.22, 0.22)
	sb.border_color = Color(0.55, 0.55, 0.55)
	sb.set_border_width_all(2)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

static func _placeholder_button_hover() -> StyleBoxFlat:
	var sb = _placeholder_button()
	sb.bg_color = Color(0.32, 0.32, 0.32)
	sb.border_color = Color(0.85, 0.85, 0.85)
	return sb

static func _placeholder_button_pressed() -> StyleBoxFlat:
	var sb = _placeholder_button()
	sb.bg_color = Color(0.15, 0.15, 0.15)
	sb.border_color = Color.WHITE
	return sb

static func _placeholder_panel() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.10, 0.94)
	sb.border_color = Color(0.45, 0.45, 0.45)
	sb.set_border_width_all(2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb

static func _polished_button() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = COL_PEACH
	sb.border_color = COL_INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb

static func _polished_button_hover() -> StyleBoxFlat:
	var sb = _polished_button()
	sb.bg_color = COL_PUMPKIN_HI
	sb.border_color = COL_INK
	sb.shadow_size = 10
	return sb

static func _polished_button_pressed() -> StyleBoxFlat:
	var sb = _polished_button()
	sb.bg_color = COL_PUMPKIN
	sb.border_color = COL_PUMPKIN_HI
	sb.shadow_size = 2
	return sb

static func _polished_button_disabled() -> StyleBoxFlat:
	var sb = _polished_button()
	sb.bg_color = COL_PEACH_DARK.lerp(Color(0.5, 0.5, 0.5), 0.5)
	sb.border_color = COL_PEACH.lerp(Color(0.5, 0.5, 0.5), 0.5)
	return sb

static func _polished_panel() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.99, 0.92, 0.80, 0.97)
	sb.border_color = COL_INK
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(22)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 8
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	return sb

static func current_theme_name() -> String:
	# Default to polished if it's unlocked, otherwise placeholder.
	var t: String = Global.settings_cfg.get("theme", "polished")
	if t == "polished" and not Global.is_unlocked("ui_polished"):
		return "placeholder"
	return t

static func apply_current(root: Node) -> void:
	apply(root, current_theme_name())

static func apply(root: Node, theme_name: String) -> void:
	if theme_name == "polished":
		_apply_polished(root)
	else:
		_apply_placeholder(root)
	apply_font_choice(root)

## When the "font_select" upgrade is bought and a font is chosen in Settings,
## override the default font on all Buttons / Labels / CheckBoxes in the tree.
## Every font this sets is tagged, so when Font Select is not owned (or has been
## toggled off) the tagged overrides are stripped again — without the tag we'd
## also strip the deliberate display fonts other screens set themselves.
static func apply_font_choice(root: Node) -> void:
	var font: Font = null
	if Global.is_unlocked("font_select"):
		var choice: String = String(Global.settings_cfg.get("font_choice", "default"))
		var path := "res://assets/fonts/%s" % choice
		if choice != "" and choice != "default" and ResourceLoader.exists(path):
			font = load(path)
	_walk(root, func(node):
		if not (node is Button or node is Label or node is OptionButton or node is LineEdit):
			return
		if font != null:
			node.add_theme_font_override("font", font)
			node.set_meta(FONT_META, true)
		elif node.has_meta(FONT_META):
			node.remove_theme_font_override("font")
			node.remove_meta(FONT_META)
	)

const FONT_META := "ui_theme_font"

static func _apply_placeholder(root: Node) -> void:
	_walk(root, func(node):
		if node is Button:
			node.add_theme_stylebox_override("normal", _placeholder_button())
			node.add_theme_stylebox_override("hover", _placeholder_button_hover())
			node.add_theme_stylebox_override("pressed", _placeholder_button_pressed())
			node.add_theme_stylebox_override("focus", _placeholder_button_hover())
			node.add_theme_color_override("font_color", Color.WHITE)
			node.add_theme_color_override("font_hover_color", Color.WHITE)
			node.add_theme_font_size_override("font_size", 22)
		elif node is Panel:
			node.add_theme_stylebox_override("panel", _placeholder_panel())
		elif node is Label:
			node.add_theme_color_override("font_color", Color.WHITE)
		elif node is HSlider or node is VSlider:
			pass
		elif node is CheckBox:
			node.add_theme_color_override("font_color", Color.WHITE)
	)

static func _apply_polished(root: Node) -> void:
	_walk(root, func(node):
		if node is CheckBox:
			# CheckBox first — it inherits from Button so the Button branch would
			# otherwise stomp its styling.
			_style_checkbox_polished(node)
		elif node is Button:
			node.add_theme_stylebox_override("normal", _polished_button())
			node.add_theme_stylebox_override("hover", _polished_button_hover())
			node.add_theme_stylebox_override("pressed", _polished_button_pressed())
			node.add_theme_stylebox_override("disabled", _polished_button_disabled())
			node.add_theme_stylebox_override("focus", _polished_button_hover())
			node.add_theme_color_override("font_color", COL_INK)
			node.add_theme_color_override("font_hover_color", COL_INK)
			node.add_theme_color_override("font_pressed_color", Color.WHITE)
			node.add_theme_color_override("font_disabled_color", COL_INK.lerp(Color(0.5, 0.5, 0.5), 0.5))
			node.add_theme_font_size_override("font_size", 26)
			_attach_button_hover_tween(node)
		elif node is Panel:
			node.add_theme_stylebox_override("panel", _polished_panel())
		elif node is Label:
			node.add_theme_color_override("font_color", COL_INK)
			node.add_theme_color_override("font_outline_color", COL_PEACH)
			node.add_theme_constant_override("outline_size", 4)
	)

## Draw a rounded pill "switch" behind the checkbox and swap the tick icons.
static func _style_checkbox_polished(cb: CheckBox) -> void:
	cb.add_theme_color_override("font_color", COL_INK)
	cb.add_theme_font_size_override("font_size", 24)
	cb.add_theme_constant_override("h_separation", 14)
	# Clear default button chrome.
	var empty := StyleBoxEmpty.new()
	cb.add_theme_stylebox_override("normal", empty)
	cb.add_theme_stylebox_override("hover", empty)
	cb.add_theme_stylebox_override("pressed", empty)
	cb.add_theme_stylebox_override("focus", empty)
	# Swap the check icons for custom "off" / "on" rounded pills so the toggle
	# actually reads as a physical switch instead of a boxy tick.
	cb.add_theme_icon_override("unchecked", _switch_icon(false))
	cb.add_theme_icon_override("checked",   _switch_icon(true))
	cb.add_theme_icon_override("unchecked_disabled", _switch_icon(false, true))
	cb.add_theme_icon_override("checked_disabled",   _switch_icon(true, true))
	cb.add_theme_icon_override("radio_unchecked", _switch_icon(false))
	cb.add_theme_icon_override("radio_checked",   _switch_icon(true))

static func _switch_icon(on: bool, disabled: bool = false) -> ImageTexture:
	# Chunky pill switch. Larger than a default checkbox so it reads as a
	# physical toggle at a glance when the polished UI upgrade is on.
	var w := 88
	var h := 44
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var track_col := (Color(0.85, 0.62, 0.24) if on else Color(0.55, 0.50, 0.45))
	if disabled: track_col = track_col.lerp(Color(0.5, 0.5, 0.5), 0.5)
	var knob_col := Color(0.99, 0.92, 0.80)
	# Track: horizontal capsule.
	for y in h:
		for x in w:
			var cx = (x if x < h * 0.5 else (w - h * 0.5 if x > w - h * 0.5 else h * 0.5))
			var dx = x - cx
			var dy = y - h * 0.5
			var in_cap: bool = (x >= h * 0.5 and x <= w - h * 0.5) or dx * dx + dy * dy <= (h * 0.5) * (h * 0.5)
			if in_cap:
				img.set_pixel(x, y, track_col)
	# Knob: circle on the side.
	var knob_r := h * 0.5 - 3
	var knob_cx := (w - h * 0.5) if on else h * 0.5
	for y in h:
		for x in w:
			var dx = x - knob_cx
			var dy = y - h * 0.5
			if dx * dx + dy * dy <= knob_r * knob_r:
				img.set_pixel(x, y, knob_col)
	return ImageTexture.create_from_image(img)

static func _walk(node: Node, cb: Callable) -> void:
	cb.call(node)
	for c in node.get_children():
		_walk(c, cb)

static func _attach_button_hover_tween(btn: Button) -> void:
	if btn.has_meta("ui_theme_hover_bound"): return
	btn.set_meta("ui_theme_hover_bound", true)
	btn.pivot_offset = btn.size * 0.5
	btn.mouse_entered.connect(func():
		if btn.disabled: return
		btn.pivot_offset = btn.size * 0.5
		btn.z_index = 5   # draw on top of sibling rows inside the VBox
		# Disable clipping on the nearest clipping ancestors so the scaled
		# button corners aren't chopped off by the panel or scroll container.
		_set_ancestor_clip(btn, false)
		var tw = btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(1.06, 1.06), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	btn.mouse_exited.connect(func():
		if btn.disabled: return
		btn.z_index = 0
		_set_ancestor_clip(btn, true)
		var tw = btn.create_tween()
		tw.tween_property(btn, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)
	)

## Walk up to the nearest Control ancestors that clip and toggle their clip_contents.
## We only touch Panel and PanelContainer parents (the ones in settings/shop/game-over)
## so we don't accidentally break top-level containers.
static func _set_ancestor_clip(node: Node, clip: bool) -> void:
	var p = node.get_parent()
	var steps := 0
	while p != null and steps < 6:
		if p is Panel or p is PanelContainer:
			(p as Control).clip_contents = clip
		p = p.get_parent()
		steps += 1

## Kept for backwards compatibility; the clip-suppression logic has been
## removed because it was disabling ScrollContainer clipping and revealing
## all off-screen rows on hover.
static func _lift_button_visibility(_btn: Button, _lift: bool) -> void:
	pass
