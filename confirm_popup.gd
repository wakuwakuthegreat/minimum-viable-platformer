extends CanvasLayer
class_name ConfirmPopup

## Small reusable "are you sure?" modal — dim + centered panel + two buttons.
## Used wherever a destructive/irreversible action (quitting the app) should
## be confirmed instead of firing immediately on a single back-press or click.

signal confirmed
signal cancelled

@onready var dim: ColorRect = $Root/Dim
@onready var panel: Panel = $Root/Center/Panel
@onready var title_label: Label = $Root/Center/Panel/V/Title
@onready var message_label: Label = $Root/Center/Panel/V/Message
@onready var btn_cancel: Button = $Root/Center/Panel/V/Buttons/Cancel
@onready var btn_confirm: Button = $Root/Center/Panel/V/Buttons/Confirm


func _ready() -> void:
	layer = 120  # Above pause_menu (60) and main_menu (95).
	process_mode = Node.PROCESS_MODE_ALWAYS  # Must work while the tree is paused.
	btn_cancel.pressed.connect(_on_cancel)
	btn_confirm.pressed.connect(_on_confirm)

	# "Confirm" reads as the dangerous choice — mark it red like the rest of
	# the app's quit styling (see main_menu.gd's topbar quit button).
	var ink := Color(1.0, 1.0, 1.0)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.55, 0.08, 0.08)
	normal.set_corner_radius_all(8)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.75, 0.12, 0.12)
	hover.set_corner_radius_all(8)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.40, 0.05, 0.05)
	pressed.set_corner_radius_all(8)
	btn_confirm.add_theme_stylebox_override("normal", normal)
	btn_confirm.add_theme_stylebox_override("hover", hover)
	btn_confirm.add_theme_stylebox_override("pressed", pressed)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn_confirm.add_theme_color_override(c, ink)

	UITheme.apply_current(self)
	# Re-apply the red override — UITheme.apply_current may have just clobbered it.
	btn_confirm.add_theme_stylebox_override("normal", normal)
	btn_confirm.add_theme_stylebox_override("hover", hover)
	btn_confirm.add_theme_stylebox_override("pressed", pressed)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn_confirm.add_theme_color_override(c, ink)

	AudioManager.connect_ui_clicks(self)

	dim.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	panel.pivot_offset = panel.size * 0.5
	var tw := create_tween()
	tw.tween_property(dim, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	btn_cancel.grab_focus()


func setup(title: String, message: String, confirm_text: String = "Leave", cancel_text: String = "Cancel") -> void:
	title_label.text = title
	message_label.text = message
	btn_confirm.text = confirm_text
	btn_cancel.text = cancel_text


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		# Mark handled before _on_cancel()'s queue_free() — never touch the
		# viewport after a call that can tear this node down.
		var vp := get_viewport()
		if vp: vp.set_input_as_handled()
		_on_cancel()


func _on_cancel() -> void:
	cancelled.emit()
	queue_free()


func _on_confirm() -> void:
	confirmed.emit()
	queue_free()


## Convenience factory: pops a "really leave?" confirm that quits the whole
## app when accepted. `host` just needs to be inside the tree.
static func ask_to_quit(host: Node, message: String) -> ConfirmPopup:
	# load(), not preload(): this scene's own script is confirm_popup.gd, so a
	# preload here would try to resolve itself while still parsing.
	var popup := load("res://confirm_popup.tscn").instantiate() as ConfirmPopup
	host.get_tree().root.add_child(popup)
	popup.setup("Really leave?", message, "Quit Game", "Keep Playing")
	popup.confirmed.connect(func(): host.get_tree().quit())
	return popup


## Convenience factory: pops a "leave this run?" confirm that returns to the
## main menu when accepted. Pauses the tree for the duration so gameplay can't
## keep going behind the popup, and unpauses on either choice. Used by the
## back-button path in pause_menu.gd for the window where "ui" is unlocked but
## "pause_menu" isn't yet — there's no pause screen there to catch the back
## press, so it would otherwise drop straight to the main menu with no chance
## to cancel.
static func ask_to_leave_run(host: Node, message: String) -> ConfirmPopup:
	var popup := load("res://confirm_popup.tscn").instantiate() as ConfirmPopup
	host.get_tree().paused = true
	host.get_tree().root.add_child(popup)
	popup.setup("Leave this run?", message, "Exit to Menu", "Resume")
	popup.confirmed.connect(func():
		host.get_tree().paused = false
		ComboSystem.reset()
		host.get_tree().change_scene_to_file("res://main_menu.tscn"))
	popup.cancelled.connect(func(): host.get_tree().paused = false)
	return popup
