extends CanvasLayer

## Always-on debug overlay. Autoloaded, survives scene changes.
## F3 toggles visibility. Reads Global.debug_toggles for the on/off state.

@onready var panel: Panel
@onready var info_label: Label
@onready var checklist_label: Label
@onready var toggle_box: VBoxContainer

var _player_ref: Node = null
var _accum: float = 0.0
var _checklist_accum: float = 0.0

func _ready() -> void:
	layer = 200
	_build_ui()
	# Honour the inspector export: if Global.debug_text (the @export flag) is set,
	# force the overlay on so the developer doesn't have to dig into a saved
	# toggle every time. Players who deliberately turned it off will still have
	# the F3 shortcut to re-enable it.
	if Global.debug_text:
		Global.debug_toggles["show_overlay"] = true
	set_process(true)

func _build_ui() -> void:
	panel = Panel.new()
	panel.anchor_left = 0
	panel.anchor_top = 0
	panel.offset_left = 8
	panel.offset_top = 8
	panel.custom_minimum_size = Vector2(330, 360)
	panel.add_theme_stylebox_override("panel", _bg())
	add_child(panel)

	var v = VBoxContainer.new()
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 10; v.offset_top = 8
	v.offset_right = -10; v.offset_bottom = -8
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var header = Label.new()
	header.text = "● debug overlay   F3 to toggle"
	header.add_theme_color_override("font_color", Color(0.95, 0.78, 0.30))
	header.add_theme_font_size_override("font_size", 14)
	v.add_child(header)

	info_label = Label.new()
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_font_size_override("font_size", 13)
	v.add_child(info_label)

	var sep1 = HSeparator.new()
	v.add_child(sep1)

	var cl_title = Label.new()
	cl_title.text = "feature checklist"
	cl_title.add_theme_color_override("font_color", Color(0.55, 0.85, 0.50))
	cl_title.add_theme_font_size_override("font_size", 13)
	v.add_child(cl_title)

	checklist_label = Label.new()
	checklist_label.add_theme_color_override("font_color", Color.WHITE)
	checklist_label.add_theme_font_size_override("font_size", 12)
	v.add_child(checklist_label)

	var sep2 = HSeparator.new()
	v.add_child(sep2)

	var tb_title = Label.new()
	tb_title.text = "debug toggles"
	tb_title.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95))
	tb_title.add_theme_font_size_override("font_size", 13)
	v.add_child(tb_title)

	toggle_box = VBoxContainer.new()
	toggle_box.add_theme_constant_override("separation", 1)
	v.add_child(toggle_box)
	_rebuild_toggle_box()

func _bg() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.10, 0.88)
	sb.border_color = Color(0.95, 0.78, 0.30, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _rebuild_toggle_box() -> void:
	for c in toggle_box.get_children():
		c.queue_free()
	for k in Global.debug_toggles.keys():
		var cb = CheckBox.new()
		cb.text = String(k).replace("_", " ")
		cb.button_pressed = Global.debug_toggles[k]
		cb.add_theme_color_override("font_color", Color.WHITE)
		cb.add_theme_font_size_override("font_size", 12)
		cb.toggled.connect(func(p: bool) -> void:
			Global.debug_toggles[k] = p
		)
		toggle_box.add_child(cb)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		Global.debug_toggles["show_overlay"] = not Global.debug_toggles.get("show_overlay", true)

func _process(_delta: float) -> void:
	var show: bool = Global.debug_toggles.get("show_overlay", true)
	panel.visible = show
	if not show: return

	_accum += _delta
	if _accum < 0.18:
		return
	_accum = 0.0

	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = _find_player()

	var fps = Engine.get_frames_per_second()
	var mem = OS.get_static_memory_usage() / (1024.0 * 1024.0)
	var nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)

	var lines: Array[String] = []
	lines.append("FPS:    %d" % fps)
	lines.append("MEM:    %.1f MB" % mem)
	lines.append("Nodes:  %d" % int(nodes))
	lines.append("Draws:  %d" % int(draw_calls))
	lines.append("Tokens: ★ %d   Best: %d m" % [Global.tokens, Global.best_distance])
	if _player_ref:
		var p = _player_ref
		var pos = p.global_position
		var vel = p.get("velocity") if p.get("velocity") != null else Vector2.ZERO
		var mom = p.get("auto_momentum") if p.get("auto_momentum") != null else 0
		var stn = p.get("stun_timer") if p.get("stun_timer") != null else 0
		lines.append("Pos:    (%d, %d)" % [pos.x, pos.y])
		lines.append("Vel:    (%d, %d)" % [vel.x, vel.y])
		lines.append("Run:    %.0f  | Stun: %.2f" % [mom, stn])
		lines.append("Run distance: %d m" % Global.last_run_distance)
	info_label.text = "\n".join(lines)

	# The skill checklist is expensive to rebuild (one lookup per skill) and
	# barely changes during gameplay — refresh it ~1/s instead of every 0.18s.
	_checklist_accum += _delta
	if _checklist_accum >= 1.0:
		_checklist_accum = 0.0
		var cl_lines: Array[String] = []
		for sid in SkillsDB.SKILLS.keys():
			var d = SkillsDB.SKILLS[sid]
			var owned = SkillsDB.is_purchased(sid)
			var mark = "✓" if owned else "·"
			cl_lines.append("[%s] %s" % [mark, d["name"]])
		checklist_label.text = "\n".join(cl_lines)

func _find_player() -> Node:
	var tree = get_tree()
	if not tree: return null
	var scene = tree.current_scene
	if not scene: return null
	return _walk_find_player(scene)

func _walk_find_player(node: Node) -> Node:
	if node.name == "Player":
		return node
	if node is CharacterBody2D and node.has_method("get_local_lowest_y"):
		return node
	for c in node.get_children():
		var r = _walk_find_player(c)
		if r: return r
	return null
