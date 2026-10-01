extends CanvasLayer
class_name GameOverUI

# Two modes:
#   PRE-UI       (no "ui" feature unlocked yet) — bare prompt to buy UI.
#   POST-UI      (ui unlocked) — compact game-over card with row-laid-out buttons,
#                stats grid (distance, best distance, best combo, tokens), and
#                copyable seed code.

@onready var dim: ColorRect      = $Dim
@onready var center: CenterContainer = $Center
@onready var box: VBoxContainer  = $Center/ScrollWrap/Box
@onready var title_label: Label  = $Center/ScrollWrap/Box/Title
@onready var tokens_earned_label: Label = $Center/ScrollWrap/Box/Earned
@onready var hint_label: Label   = $Center/ScrollWrap/Box/Hint

@onready var btn_buy_ui: Button   = $Center/ScrollWrap/Box/Buttons/BuyUIButton
@onready var btn_retry: Button    = $Center/ScrollWrap/Box/Buttons/RetryButton
@onready var btn_shop: Button     = $Center/ScrollWrap/Box/Buttons/ShopButton
@onready var btn_menu: Button     = $Center/ScrollWrap/Box/Buttons/MenuButton
@onready var btn_exit: Button     = $Center/ScrollWrap/Box/Buttons/ExitButton
@onready var buttons_box: VBoxContainer = $Center/ScrollWrap/Box/Buttons

## Dynamically created inline cause row ("💀 killed by …") — small, tucked under
## the title so it doesn't own its own vertical band.
var _cause_row: HBoxContainer = null

## Stats card — a 2-column icon+value grid tucked between the header and the
## button block. All the end-of-run numbers live here.
const StatIconScene := preload("res://stat_icon.gd")
var _stats_card: PanelContainer = null
var _stats_grid: GridContainer = null
var _stat_val_distance: Label = null
var _stat_val_best_dist: Label = null
var _stat_val_combo: Label = null
var _stat_val_tokens: Label = null
var _stat_row_distance: HBoxContainer = null
var _stat_row_best_dist: HBoxContainer = null
var _stat_row_combo: HBoxContainer = null
var _stat_row_tokens: HBoxContainer = null

## Seed strip: label + code + copy button. Its own row so the copy button can
## sit inline with the code without upsetting the 2-col stats grid.
var _seed_strip: PanelContainer = null
var _seed_code_label: Label = null
var _seed_copy_btn: Button = null
var _seed_best_label: Label = null

## Replay + favourite buttons (library-gated).
var _replay_btn: Button = null
var _save_btn: Button = null
var btn_leaderboard: Button = null

var _last_tokens_awarded: int = 0
var _last_distance_m: int = 0

var _profile_strip: PanelContainer = null
var _profile_name_label: Label = null
var _profile_edit_btn: Button = null

## Row containers used by the compact button layout — kept around so we can
## reparent buttons between rows without leaking old containers on repeated
## show_game_over calls.
var _btn_row_primary: HBoxContainer = null   # Replay / Retry / Shop
var _btn_row_secondary: HBoxContainer = null # Menu / Exit

## Ephemeral "Copied!" toast anchored to the copy button.
var _toast: Label = null

## Rewarded-ad offer: doubles the tokens this run paid out. Sits under the stats
## card, above the hint, so it reads as an extension of the numbers it doubles.
var _double_btn: Button = null
## One claim per game-over. Reset at the top of show_game_over().
var _double_claimed: bool = false

func _ready() -> void:
	layer = 95
	visible = false
	btn_buy_ui.pressed.connect(_on_buy_ui)
	btn_retry.pressed.connect(_on_retry)
	btn_shop.pressed.connect(_on_shop)
	btn_menu.pressed.connect(_on_menu)
	btn_exit.pressed.connect(_on_exit)

	btn_leaderboard = Button.new()
	btn_leaderboard.pressed.connect(_on_leaderboard)
	AudioManager.connect_ui_clicks(self)

func show_game_over(tokens_awarded: int = 0, distance_m: int = 0) -> void:
	visible = true
	_last_tokens_awarded = tokens_awarded
	_last_distance_m = distance_m
	_double_claimed = false
	var has_ui := Global.is_unlocked("ui")

	# Sizing: let the ScrollWrap collapse to its content height so there's no
	# empty band under the buttons. Vertical scrolling is disabled — if content
	# overflows a tiny viewport we accept clipping over the previous "500 px of
	# blank space beneath the buttons" look. Horizontal scroll stays disabled.
	var vp := get_viewport().get_visible_rect().size
	var wrap: ScrollContainer = $Center/ScrollWrap
	var side_pad: float = max(24.0, vp.x * 0.04)
	var target_w: float = clamp(vp.x - side_pad * 2.0, 320.0, 720.0)
	wrap.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.custom_minimum_size = Vector2(target_w, 0)
	# Scroll is disabled, so clipping only ends up eating the hover-scale and
	# jiggle animations on our buttons. Turn it off explicitly.
	wrap.clip_contents = false
	var inner_box: VBoxContainer = $Center/ScrollWrap/Box
	inner_box.custom_minimum_size = Vector2(target_w - 40.0, 0)
	inner_box.add_theme_constant_override("separation", 10)

	# Compact title — smaller than before so the card doesn't lead with a giant
	# banner. On narrow screens it scales down further so the header + cause row
	# never wrap.
	title_label.add_theme_font_size_override("font_size", int(clamp(vp.x * 0.06, 40, 64)))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	tokens_earned_label.visible = not has_ui
	tokens_earned_label.add_theme_font_size_override("font_size", 34)
	tokens_earned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	hint_label.add_theme_font_size_override("font_size", int(clamp(vp.x * 0.028, 18, 22)))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if has_ui:
		_configure_post_ui(tokens_awarded, distance_m)
	else:
		_configure_pre_ui(tokens_awarded)

	_update_cause_row()

	# Stats card + seed strip are only meaningful post-UI.
	if has_ui:
		_ensure_stats_card()
		_populate_stats_card(tokens_awarded, distance_m, target_w)
		_ensure_profile_strip()
		_populate_profile_strip()
		_ensure_seed_strip()
		_populate_seed_strip()
		_check_and_submit_leaderboard()
		if _stats_card: _stats_card.visible = true
		_ensure_double_btn()
		_refresh_double_btn()
	else:
		if _stats_card: _stats_card.visible = false
		if _profile_strip: _profile_strip.visible = false
		if _seed_strip: _seed_strip.visible = false
		if _double_btn: _double_btn.visible = false

	_style_buttons(target_w, has_ui)

	UITheme.apply_current(self)
	_play_in_tween()

# ─── STATS CARD ────────────────────────────────────────────────────────

## Build the stats-card panel once and cache references to its value labels.
func _ensure_stats_card() -> void:
	if _stats_card and is_instance_valid(_stats_card):
		return
	_stats_card = PanelContainer.new()
	_stats_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.94, 0.80, 0.85)
	sb.border_color = Color(0.42, 0.30, 0.18, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_stats_card.add_theme_stylebox_override("panel", sb)

	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.add_theme_constant_override("h_separation", 20)
	_stats_grid.add_theme_constant_override("v_separation", 8)
	_stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_card.add_child(_stats_grid)

	_stat_val_distance  = _add_stat_row(StatIconScene.Kind.FLAG,   "0 m")
	_stat_val_best_dist = _add_stat_row(StatIconScene.Kind.TROPHY, "best 0 m")
	_stat_val_combo     = _add_stat_row(StatIconScene.Kind.FIRE,   "no combo")
	_stat_val_tokens    = _add_stat_row(StatIconScene.Kind.STAR,   "+0 ★")

	_stat_row_distance  = _stat_val_distance.get_parent()
	_stat_row_best_dist = _stat_val_best_dist.get_parent()
	_stat_row_combo     = _stat_val_combo.get_parent()
	_stat_row_tokens    = _stat_val_tokens.get_parent()

	# Card sits directly after the cause row (or title if no cause) and before
	# the seed strip / hint / buttons.
	var target_idx: int = hint_label.get_index()
	box.add_child(_stats_card)
	box.move_child(_stats_card, target_idx)

func _add_stat_row(kind: int, initial_text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var icon := Control.new()
	icon.set_script(StatIconScene)
	icon.set("kind", kind)
	icon.custom_minimum_size = Vector2(32, 32)
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text = initial_text
	lbl.add_theme_color_override("font_color", Color(0.15, 0.10, 0.06))
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	_stats_grid.add_child(row)
	return lbl

func _populate_stats_card(tokens_awarded: int, distance_m: int, panel_w: float) -> void:
	if _stats_card == null: return
	# Narrow phones drop the grid to a single column so nothing truncates.
	_stats_grid.columns = 2 if panel_w >= 460.0 else 1

	_stat_val_distance.text  = "%d m" % distance_m
	_stat_val_best_dist.text = "best %d m" % Global.best_distance
	_stat_val_tokens.text    = "+%d ★" % tokens_awarded

	var best_combo: int = int(Global.stats.get("longest_combo", 0))
	if best_combo > 0:
		_stat_val_combo.text = "x%d combo" % best_combo
		_stat_row_combo.visible = true
	else:
		# No combos ever recorded — hide the row to save vertical space.
		_stat_row_combo.visible = false

# ─── SEED STRIP ────────────────────────────────────────────────────────

## Seed code + copy button + best-on-seed hint. Lives in its own panel so the
## copy button can sit inline without perturbing the stats grid.
func _ensure_seed_strip() -> void:
	if _seed_strip and is_instance_valid(_seed_strip):
		return
	_seed_strip = PanelContainer.new()
	_seed_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.90, 0.72, 0.75)
	sb.border_color = Color(0.42, 0.30, 0.18, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_seed_strip.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_strip.add_child(row)

	var hash_icon := Control.new()
	hash_icon.set_script(StatIconScene)
	hash_icon.set("kind", StatIconScene.Kind.HASH)
	hash_icon.custom_minimum_size = Vector2(28, 28)
	row.add_child(hash_icon)

	_seed_code_label = Label.new()
	_seed_code_label.add_theme_font_size_override("font_size", 24)
	_seed_code_label.add_theme_color_override("font_color", Color(0.15, 0.10, 0.06))
	_seed_code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_seed_code_label)

	_seed_best_label = Label.new()
	_seed_best_label.add_theme_font_size_override("font_size", 18)
	_seed_best_label.add_theme_color_override("font_color", Color(0.28, 0.20, 0.10))
	_seed_best_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_seed_best_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_seed_best_label)

	_seed_copy_btn = Button.new()
	_seed_copy_btn.text = "Copy"
	_seed_copy_btn.custom_minimum_size = Vector2(96, 40)
	_seed_copy_btn.add_theme_font_size_override("font_size", 18)
	_seed_copy_btn.pressed.connect(_on_copy_seed)
	row.add_child(_seed_copy_btn)

	# Insert seed strip right after the stats card.
	var stats_idx: int = _stats_card.get_index() if _stats_card else hint_label.get_index()
	box.add_child(_seed_strip)
	box.move_child(_seed_strip, stats_idx + 1)

	# Toast overlay ("Copied!") — parented to the CanvasLayer so it isn't
	# force-sized by the PanelContainer; positioned above the copy button in
	# _show_toast.
	_toast = Label.new()
	_toast.text = "Copied!"
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.98, 0.85))
	_toast.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.08))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_toast.z_index = 200
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)

func _populate_seed_strip() -> void:
	if _seed_strip == null: return
	if not Global.is_unlocked("level_library") or Global.current_run_seed == 0:
		_seed_strip.visible = false
		return
	_seed_strip.visible = true
	_seed_code_label.text = "Seed  %s" % Global.seed_to_code(Global.current_run_seed)
	var best_on_seed := _best_for_current_seed()
	if best_on_seed > 0:
		_seed_best_label.text = "best on seed  %d m" % best_on_seed
		_seed_best_label.visible = true
	else:
		_seed_best_label.visible = false

func _on_copy_seed() -> void:
	if Global.current_run_seed == 0: return
	DisplayServer.clipboard_set(Global.seed_to_code(Global.current_run_seed))
	_show_toast()

func _show_toast() -> void:
	if _toast == null or _seed_copy_btn == null: return
	_toast.reset_size()
	# Pin toast to global screen coords of the copy button.
	var btn_rect: Rect2 = _seed_copy_btn.get_global_rect()
	_toast.position = Vector2(
		btn_rect.position.x + btn_rect.size.x * 0.5 - _toast.size.x * 0.5,
		btn_rect.position.y - _toast.size.y - 8.0)
	_toast.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.9)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.30)

# ─── CAUSE ROW ─────────────────────────────────────────────────────────

func _update_cause_row() -> void:
	var cause: String = Global.last_death_cause
	if cause == "":
		if _cause_row: _cause_row.visible = false
		return
	if _cause_row == null:
		_cause_row = HBoxContainer.new()
		_cause_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_cause_row.add_theme_constant_override("separation", 8)
		var icon := Control.new()
		icon.set_script(StatIconScene)
		icon.set("kind", StatIconScene.Kind.SKULL)
		icon.custom_minimum_size = Vector2(28, 28)
		_cause_row.add_child(icon)
		var lbl := Label.new()
		lbl.name = "CauseText"
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.20, 0.12, 0.08))
		_cause_row.add_child(lbl)
		box.add_child(_cause_row)
		# Sit just under the title.
		box.move_child(_cause_row, 1)
	_cause_row.visible = true
	var lbl2: Label = _cause_row.get_node("CauseText")
	lbl2.text = "killed by %s" % cause

# ─── BUTTONS ───────────────────────────────────────────────────────────

## Row layout: primary actions (Replay/Retry/Shop) share a row, secondary
## (Menu/Exit) share another. Pre-UI mode swaps in the giant BuyUI button.
func _style_buttons(target_w: float, has_ui: bool) -> void:
	# Give buttons_box zero vertical footprint of its own — the row HBoxes take
	# over sizing. Bump inter-row separation so rows don't cram together.
	buttons_box.add_theme_constant_override("separation", 10)
	# Buttons box must fill its parent's width so rows can spread horizontally.
	buttons_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_ensure_button_rows()

	# Reset icon insets stamped in previous shows so we can restyle cleanly.
	_reset_button_icons()

	if not has_ui:
		# Pre-UI: stack a single full-width BuyUI button + Retry + Exit. No shop
		# or menu button. Keep them in a single column since there's only three.
		_move_button(btn_buy_ui, buttons_box)
		_move_button(btn_retry,  buttons_box)
		_move_button(btn_exit,   buttons_box)
		_hide_button(btn_shop)
		_hide_button(btn_menu)
		_hide_button(btn_leaderboard)
		if _replay_btn: _replay_btn.visible = false
		# Row containers unused in this mode.
		_btn_row_primary.visible = false
		_btn_row_secondary.visible = false
		# Bare-bones on purpose: this screen exists before the player owns any
		# "ui" polish, so it shouldn't borrow any — no icons, no color-coding,
		# no tilt (see _juice_primary_button). Plain text in a white-outlined box.
		btn_exit.text = "Exit"
		_style_bare_outline_button(btn_buy_ui, target_w * 0.9, 64)
		_style_bare_outline_button(btn_retry,  target_w * 0.9, 60)
		_style_bare_outline_button(btn_exit,   target_w * 0.9, 60)
		return

	# Post-UI: build the button rows.
	_hide_button(btn_buy_ui)
	_btn_row_primary.visible = true
	_btn_row_secondary.visible = true

	# Row 1: Replay (if library) + Retry + Shop
	_ensure_replay_btn()
	if _replay_btn and Global.is_unlocked("level_library"):
		_move_button(_replay_btn, _btn_row_primary)
		_replay_btn.visible = true
	elif _replay_btn:
		_replay_btn.visible = false
	_move_button(btn_retry, _btn_row_primary)
	_move_button(btn_shop,  _btn_row_primary)

	# Row 2: Menu + Exit + Leaderboard
	_move_button(btn_menu, _btn_row_secondary)
	_move_button(btn_exit, _btn_row_secondary)
	if Global.is_unlocked("leaderboard"):
		_move_button(btn_leaderboard, _btn_row_secondary)
	else:
		_hide_button(btn_leaderboard)

	# Style each button for row use — small enough that 3 fit per row.
	var row_btn_h: int = 56
	var row_btn_fs: int = 20
	var row_btn_min_w: int = int(clamp(target_w / 3.4, 140, 220))
	if _replay_btn and _replay_btn.visible:
		_style_row_button(_replay_btn, StatIconScene.Kind.REDO,  row_btn_min_w, row_btn_h, row_btn_fs, "Replay")
		# Retry becomes "New" now that Replay owns the "same seed" action.
		_style_row_button(btn_retry, StatIconScene.Kind.DICE, row_btn_min_w, row_btn_h, row_btn_fs, "New")
	else:
		# Without Replay, Retry keeps its "Run again / New Level" label.
		var retry_kind: int = StatIconScene.Kind.DICE if Global.is_unlocked("level_library") else StatIconScene.Kind.REDO
		_style_row_button(btn_retry, retry_kind, row_btn_min_w, row_btn_h, row_btn_fs, btn_retry.text.strip_edges())
	_style_row_button(btn_shop, StatIconScene.Kind.BAG, row_btn_min_w, row_btn_h, row_btn_fs, "Shop (%d ★)" % Global.tokens)

	var sec_min_w: int = row_btn_min_w if Global.is_unlocked("leaderboard") else int(clamp(target_w / 2.3, 180, 320))
	_style_row_button(btn_menu, StatIconScene.Kind.HOME, sec_min_w, 52, 20, "Menu")
	_style_row_button(btn_exit, StatIconScene.Kind.DOOR, sec_min_w, 52, 20, "Exit")
	# Make exit stand out with a reddish tint.
	var exit_sb := StyleBoxFlat.new()
	exit_sb.bg_color = Color(0.75, 0.18, 0.12, 0.90)
	exit_sb.border_color = Color(0.95, 0.30, 0.22, 0.80)
	exit_sb.set_border_width_all(2)
	exit_sb.set_corner_radius_all(10)
	exit_sb.content_margin_left = 12; exit_sb.content_margin_right = 12
	exit_sb.content_margin_top = 8; exit_sb.content_margin_bottom = 8
	btn_exit.add_theme_stylebox_override("normal", exit_sb)
	btn_exit.add_theme_color_override("font_color", Color(1, 0.92, 0.88))
	if Global.is_unlocked("leaderboard"):
		_style_row_button(btn_leaderboard, StatIconScene.Kind.TROPHY, sec_min_w, 52, 20, "Leaderboard")

	# Favourite button — full width under the secondary row (library-gated).
	_ensure_save_button()
	if _save_btn:
		_move_button(_save_btn, buttons_box)
		_style_row_button(_save_btn, StatIconScene.Kind.STAR, int(target_w * 0.9), 52, 20, _save_btn.text.strip_edges())

func _ensure_button_rows() -> void:
	if _btn_row_primary == null or not is_instance_valid(_btn_row_primary):
		_btn_row_primary = HBoxContainer.new()
		_btn_row_primary.add_theme_constant_override("separation", 10)
		_btn_row_primary.alignment = BoxContainer.ALIGNMENT_CENTER
		_btn_row_primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons_box.add_child(_btn_row_primary)
	if _btn_row_secondary == null or not is_instance_valid(_btn_row_secondary):
		_btn_row_secondary = HBoxContainer.new()
		_btn_row_secondary.add_theme_constant_override("separation", 10)
		_btn_row_secondary.alignment = BoxContainer.ALIGNMENT_CENTER
		_btn_row_secondary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons_box.add_child(_btn_row_secondary)
	# Ensure rows come before the favourite button (added later).
	buttons_box.move_child(_btn_row_primary,   0)
	buttons_box.move_child(_btn_row_secondary, 1)

## Reparent a button to `target_parent`. Keeps signal connections intact.
func _move_button(btn: Button, target_parent: Node) -> void:
	if btn == null: return
	btn.visible = true
	if btn.get_parent() == target_parent: return
	if btn.get_parent(): btn.get_parent().remove_child(btn)
	target_parent.add_child(btn)

func _hide_button(btn: Button) -> void:
	if btn: btn.visible = false

## Clear cached icon so we can restyle labels/sizes across mode switches.
## Existing icon children are also freed so we don't stack duplicates.
func _reset_button_icons() -> void:
	for b in [btn_buy_ui, btn_retry, btn_shop, btn_menu, btn_exit, _replay_btn, _save_btn, btn_leaderboard]:
		if b == null: continue
		if b.has_meta("ui_icon_node"):
			var old = b.get_meta("ui_icon_node")
			if old and is_instance_valid(old):
				old.queue_free()
			b.remove_meta("ui_icon_node")

## Pre-UI styling: a plain white-outlined box with plain text — no icon, no
## color-coding. Used for every button on the pre-UI game-over screen (see
## _style_buttons).
func _style_bare_outline_button(btn: Button, min_w: float, h: int) -> void:
	btn.custom_minimum_size = Vector2(min_w, h)
	btn.add_theme_font_size_override("font_size", 24)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.06)
	normal.border_color = Color(1, 1, 1, 0.9)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12; normal.content_margin_right = 12
	normal.content_margin_top = 8; normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.16)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1, 1, 1, 0.28)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(1, 1, 1, 0.03)
	disabled.border_color = Color(1, 1, 1, 0.4)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_stylebox_override("disabled", disabled)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(c, Color(1, 1, 1))
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))

func _style_row_button(btn: Button, kind: int, min_w: int, h: int, fs: int, label_text: String) -> void:
	btn.custom_minimum_size = Vector2(min_w, h)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", fs)
	btn.text = "   %s" % label_text
	_attach_button_icon(btn, kind, 22, 14)

## Absolutely-position a small icon on the left of the button. The button's
## text is prefixed with spaces so it doesn't collide with the icon.
func _attach_button_icon(btn: Button, kind: int, icon_size: int, inset_x: float) -> void:
	if btn == null: return
	var icon := Control.new()
	icon.set_script(StatIconScene)
	icon.set("kind", kind)
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_top = -icon_size * 0.5
	icon.offset_bottom = icon_size * 0.5
	icon.offset_left = inset_x
	icon.offset_right = inset_x + icon_size
	btn.add_child(icon)
	btn.set_meta("ui_icon_node", icon)

# ─── DYNAMIC BUTTONS (library-gated) ────────────────────────────────────

func _ensure_replay_btn() -> void:
	if not Global.is_unlocked("level_library"):
		if _replay_btn:
			_replay_btn.visible = false
		return
	if _replay_btn == null or not is_instance_valid(_replay_btn):
		_replay_btn = Button.new()
		_replay_btn.pressed.connect(_on_replay_same)
		# Row parent is assigned in _style_buttons.

func _ensure_save_button() -> void:
	if not Global.is_unlocked("level_library"):
		if _save_btn:
			_save_btn.queue_free()
			_save_btn = null
		return
	if _save_btn == null or not is_instance_valid(_save_btn):
		_save_btn = Button.new()
		_save_btn.pressed.connect(_on_favourite_level)
	# Update label based on favourite state.
	var already_fav := false
	for entry in Global.level_library:
		if int(entry.get("seed", 0)) == Global.current_run_seed:
			if bool(entry.get("favorite", false)):
				already_fav = true
			break
	_save_btn.text = "Favourited!" if already_fav else "Favourite this level"
	_save_btn.disabled = already_fav

func _best_for_current_seed() -> int:
	for entry in Global.level_library:
		if int(entry.get("seed", 0)) == Global.current_run_seed:
			return int(entry.get("distance", 0))
	return 0

func _on_replay_same() -> void:
	var level_gen = load("res://level_generator.gd")
	if level_gen:
		level_gen.current_seed = Global.current_run_seed
	get_tree().reload_current_scene()

func _configure_pre_ui(tokens_awarded: int) -> void:
	title_label.text = "you died."
	tokens_earned_label.text = "+%d ★ token" % tokens_awarded
	hint_label.text = "Buy UI to unlock the menus, shop and more."
	btn_buy_ui.visible = true
	btn_buy_ui.text = "Buy UI (1 ★)"
	btn_buy_ui.disabled = Global.tokens < 1
	btn_retry.visible = true
	btn_retry.text = "Run again"
	btn_shop.visible = false
	btn_menu.visible = false
	btn_exit.visible = true
	# Forced guide: talks, then points the finger at Buy UI. No-ops once bought.
	Onboarding.attach.call_deferred(self, "game_over")

func _configure_post_ui(tokens_awarded: int, distance_m: int) -> void:
	title_label.text = "you died."
	tokens_earned_label.text = "+%d ★   |   %d m" % [tokens_awarded, distance_m]
	hint_label.text = StoryDB.taunt(
		Global.last_death_cause, distance_m, int(Global.stats.get("deaths", 0)))
	btn_buy_ui.visible = false
	btn_retry.visible = true
	btn_retry.text = "New" if Global.is_unlocked("level_library") else "Run again"
	btn_shop.visible = true
	btn_shop.text = "Shop (%d ★)" % Global.tokens
	btn_menu.visible = true
	btn_exit.visible = true
	# Polish guide: only does anything once a death armed it and something in
	# its chain is still unbought. Deferred so the buttons have their final
	# layout rect before the finger measures one.
	Onboarding.attach.call_deferred(self, "game_over")

func _play_in_tween() -> void:
	box.modulate.a = 0.0
	box.scale = Vector2(0.85, 0.85)
	box.pivot_offset = box.size * 0.5
	dim.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(dim, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(box, "modulate:a", 1.0, 0.30)
	tw.parallel().tween_property(box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	call_deferred("_juice_primary_button")

## The primary action ("Replay" if library is unlocked, else "Retry" / "Run again")
## gets a little grow + jiggle so the eye lands on it, and settles at a small tilt
## for character. Post-UI only — pre-UI stays static (see the early return below).
func _juice_primary_button() -> void:
	# Pre-UI is bare on purpose — no tilt/wiggle, just a static text box.
	if not Global.is_unlocked("ui"):
		return
	# ...unless a guide owns the player's attention. Before the first guide is
	# finished the next action is whatever the finger is about to point at, and
	# while a finger is up nothing else on screen should be waving for a tap.
	if Onboarding.suppresses_juice():
		return
	var btn: Button = _pick_primary_button()
	if btn == null or not is_instance_valid(btn):
		return
	# Center the pivot so scale/rotate happens around the button's middle.
	btn.pivot_offset = btn.size * 0.5
	btn.scale = Vector2(0.6, 0.6)
	btn.rotation = 0.0
	# Draw the jiggling button above siblings and unclip ancestors so the
	# scaled/rotated corners aren't chopped off by the row container or the
	# ScrollWrap around them.
	btn.z_index = 5
	UITheme._lift_button_visibility(btn, true)
	var tw := create_tween()
	# Pop up to slightly-larger-than-siblings.
	tw.tween_property(btn, "scale", Vector2(1.15, 1.15), 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Wiggle rotation back and forth, ending at a resting tilt.
	tw.parallel().tween_property(btn, "rotation", deg_to_rad(-14.0), 0.10) \
		.set_delay(0.14).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(btn, "rotation", deg_to_rad(11.0), 0.12) \
		.set_delay(0.24).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(btn, "rotation", deg_to_rad(-7.0), 0.10) \
		.set_delay(0.36).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(btn, "rotation", deg_to_rad(-4.5), 0.18) \
		.set_delay(0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _pick_primary_button() -> Button:
	if btn_buy_ui and btn_buy_ui.visible:
		return btn_buy_ui
	if _replay_btn and is_instance_valid(_replay_btn) and _replay_btn.visible:
		return _replay_btn
	if btn_retry and btn_retry.visible:
		return btn_retry
	return null

# ─── REWARDED-AD OFFER ────────────────────────────────────────────────

## Build the double-tokens button once. Placed immediately before the hint
## label, which puts it below the stats card and seed strip and above the
## action rows — an offer, not a primary action.
func _ensure_double_btn() -> void:
	if _double_btn and is_instance_valid(_double_btn):
		return
	_double_btn = Button.new()
	_double_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_double_btn.custom_minimum_size = Vector2(0, 52)
	_double_btn.add_theme_font_size_override("font_size", 20)
	_double_btn.pressed.connect(_on_double_tokens)
	box.add_child(_double_btn)
	box.move_child(_double_btn, hint_label.get_index())

## Shown only when there is something to double, an ad to show, and the offer
## hasn't already been taken for this death.
func _refresh_double_btn() -> void:
	if _double_btn == null or not is_instance_valid(_double_btn): return
	var offerable := _last_tokens_awarded > 0 and IAP.ads_enabled() and not _double_claimed
	_double_btn.visible = offerable
	_double_btn.disabled = false
	if offerable:
		_double_btn.text = "▶  Watch a sponsor spot  →  +%d ★" % _last_tokens_awarded

func _on_double_tokens() -> void:
	if _double_claimed or _last_tokens_awarded <= 0: return
	_double_btn.disabled = true
	_double_btn.text = "Loading…"
	var bonus := _last_tokens_awarded
	var earned: bool = await IAP.show_rewarded(IAP.PLACEMENT_DOUBLE_TOKENS)
	# A real ad hands control to another activity; this card may be gone by now.
	if not is_instance_valid(self) or not is_inside_tree(): return
	if not earned:
		AudioManager.play("ui_glass", -4.0, 0.05)
		_double_btn.text = "No ad available right now"
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(_double_btn):
			_refresh_double_btn()
		return
	_double_claimed = true
	Global.grant_ad_bonus_tokens(bonus)
	AudioManager.play("ui_buy", 0.0, 0.04)
	_double_btn.visible = false
	# Restate the payout so the reward is visible where the original number was.
	tokens_earned_label.text = "+%d ★   |   %d m" % [_last_tokens_awarded + bonus, _last_distance_m]
	if _stat_val_tokens and is_instance_valid(_stat_val_tokens):
		_stat_val_tokens.text = "+%d ★" % (_last_tokens_awarded + bonus)
	# The shop button prints the live token count in its label.
	if btn_shop and is_instance_valid(btn_shop):
		btn_shop.text = "Shop (%d ★)" % Global.tokens

# ─── BUTTON HANDLERS ──────────────────────────────────────────────────

func _on_buy_ui() -> void:
	if Global.tokens < 1: return
	if Global.spend(1):
		Global.grant("ui")
		Onboarding.advance_to(Onboarding.STEP_MENU)
		get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_retry() -> void:
	var level_gen = load("res://level_generator.gd")
	if level_gen and not Global.debug_toggles.get("keep_seed", false):
		level_gen.current_seed = 0
	get_tree().reload_current_scene()

func _on_shop() -> void:
	get_tree().change_scene_to_file("res://shop.tscn")

func _on_menu() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_exit() -> void:
	get_tree().quit()

func _on_leaderboard() -> void:
	LeaderboardService.current_view_seed = Global.seed_to_code(Global.current_run_seed)
	get_tree().change_scene_to_file("res://leaderboard_view.tscn")

func _check_and_submit_leaderboard() -> void:
	if not Global.is_unlocked("leaderboard"):
		return
		
	if Global.is_unlocked("player_name"):
		if LeaderboardService.has_unique_name():
			if LeaderboardService.name_is_registered():
				_submit_score(LeaderboardService.get_player_name())
			else:
				# Player has a name from before the global-uniqueness feature —
				# claim it (may add a suffix) before submitting so the board only
				# ever sees the unique form.
				LeaderboardService.claim_unique_name(LeaderboardService.get_player_name(), func(resolved: String, _suffixed: bool):
					_populate_profile_strip()
					_submit_score(resolved)
				)
		else:
			# Prompt player to choose a unique profile name
			var dialog_script = load("res://enter_name_dialog.gd")
			if dialog_script:
				var dialog = dialog_script.new()
				dialog.allow_cancel = false # Force them to set a name to submit
				dialog.name_submitted.connect(func(new_name):
					_populate_profile_strip()
					_submit_score(new_name)
				)
				add_child(dialog)
	else:
		# If player profile custom name is locked, submit anonymously
		_submit_score("Anonymous")

func _submit_score(p_name: String) -> void:
	var seed_code = Global.seed_to_code(Global.current_run_seed)
	var p_id = LeaderboardService.player_id
	var score = Global.current_run_score
	var distance = _last_distance_m
	var combo = Global.current_run_highest_combo
	
	LeaderboardService.submit_level_result(seed_code, p_id, p_name, score, distance, combo)

func _ensure_profile_strip() -> void:
	if _profile_strip and is_instance_valid(_profile_strip):
		return
	_profile_strip = PanelContainer.new()
	_profile_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.90, 0.95, 0.91, 0.85)
	sb.border_color = Color(0.36, 0.50, 0.20, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_profile_strip.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_strip.add_child(row)

	var star_icon := Control.new()
	star_icon.set_script(StatIconScene)
	star_icon.set("kind", StatIconScene.Kind.STAR)
	star_icon.custom_minimum_size = Vector2(28, 28)
	row.add_child(star_icon)

	_profile_name_label = Label.new()
	_profile_name_label.add_theme_font_size_override("font_size", 24)
	_profile_name_label.add_theme_color_override("font_color", Color(0.15, 0.10, 0.06))
	_profile_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_profile_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_profile_name_label)

	_profile_edit_btn = Button.new()
	_profile_edit_btn.text = "Edit Name"
	_profile_edit_btn.custom_minimum_size = Vector2(110, 40)
	_profile_edit_btn.add_theme_font_size_override("font_size", 18)
	_profile_edit_btn.pressed.connect(_on_edit_profile_name)
	row.add_child(_profile_edit_btn)

	var stats_idx = _stats_card.get_index() if _stats_card else hint_label.get_index()
	box.add_child(_profile_strip)
	box.move_child(_profile_strip, stats_idx)

func _populate_profile_strip() -> void:
	if _profile_strip == null: return
	if not Global.is_unlocked("player_name"):
		_profile_strip.visible = false
		return
	_profile_strip.visible = true
	_profile_name_label.text = "Player:  %s" % LeaderboardService.get_player_name()

func _on_edit_profile_name() -> void:
	var dialog_script = load("res://enter_name_dialog.gd")
	if dialog_script:
		var dialog = dialog_script.new()
		dialog.allow_cancel = true
		dialog.name_submitted.connect(func(new_name):
			_populate_profile_strip()
			_submit_score(new_name)
		)
		add_child(dialog)

func _on_favourite_level() -> void:
	for entry in Global.level_library:
		if int(entry.get("seed", 0)) == Global.current_run_seed:
			entry["favorite"] = true
			Global.save_state()
			if _save_btn:
				_save_btn.text = "Favourited!"
				_save_btn.disabled = true
			return
	# Not in library yet — add it now.
	Global.level_library.append({
		"seed": Global.current_run_seed,
		"distance": Global.last_run_distance,
		"favorite": true,
	})
	Global.save_state()
	if _save_btn:
		_save_btn.text = "★ Favourited!"
		_save_btn.disabled = true
