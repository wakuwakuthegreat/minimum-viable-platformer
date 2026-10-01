extends CanvasLayer

@onready var root: Control = $Root
@onready var dim: ColorRect = $Root/Dim
@onready var panel: Panel = $Root/Center/Panel
@onready var btn_resume: Button = $Root/Center/Panel/V/Resume
@onready var btn_shop: Button = $Root/Center/Panel/V/Shop
@onready var btn_menu: Button = $Root/Center/Panel/V/Menu
@onready var btn_exit: Button = $Root/Center/Panel/V/Exit

## Referenced by path, not the global "ConfirmPopup" class name — that name
## is only registered once the editor rescans the project for class_name
## declarations, which a freshly-added script may not have gone through yet.
const ConfirmPopupScript := preload("res://confirm_popup.gd")

## Open "really quit?" confirmation, if one is currently up.
var _quit_popup: CanvasLayer = null

## Open "leave this run?" confirmation, if one is currently up. Only reachable
## via the back-button path below (there's no dedicated button for it).
var _leave_popup: CanvasLayer = null

func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	btn_resume.pressed.connect(_resume)
	btn_shop.pressed.connect(_to_shop)
	btn_menu.pressed.connect(_to_menu)
	btn_exit.pressed.connect(_open_quit_confirm)
	UITheme.apply_current(self)
	AudioManager.connect_ui_clicks(self)

func _input(event: InputEvent) -> void:
	if _quit_popup or _leave_popup: return
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		# Mark handled before anything that can free/replace this node
		# (change_scene_to_file, quit) — never touch the viewport after that.
		var vp := get_viewport()
		if vp: vp.set_input_as_handled()
		if Global.is_unlocked("pause_menu"):
			if visible: _resume()
			else: _show()
		else:
			if Global.is_unlocked("ui"):
				_open_leave_confirm()
			else:
				# No menu exists yet to leave to or confirm through — keep the
				# old immediate-quit behavior for this very-early state. Flag
				# it so StoryDB can needle them about it on the next run —
				# save_state() runs synchronously, so it lands before quit().
				Global.early_quit_before_unlock = true
				Global.save_state()
				get_tree().quit()

func _open_quit_confirm() -> void:
	if _quit_popup: return
	_quit_popup = ConfirmPopupScript.ask_to_quit(self, "You'll lose this run's progress.")
	_quit_popup.tree_exited.connect(func(): _quit_popup = null)

func _open_leave_confirm() -> void:
	if _leave_popup: return
	_leave_popup = ConfirmPopupScript.ask_to_leave_run(self, "You'll lose this run's progress.")
	_leave_popup.tree_exited.connect(func(): _leave_popup = null)

func _show() -> void:
	visible = true
	get_tree().paused = true
	dim.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	panel.pivot_offset = panel.size * 0.5
	var tw = create_tween()
	tw.tween_property(dim, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _resume() -> void:
	get_tree().paused = false
	visible = false

func _to_shop() -> void:
	get_tree().paused = false
	ComboSystem.reset()
	get_tree().change_scene_to_file("res://shop.tscn")

func _to_menu() -> void:
	get_tree().paused = false
	ComboSystem.reset()
	get_tree().change_scene_to_file("res://main_menu.tscn")
