extends Control

## Mouse-navigable skill-tree drawer. Emits skill_selected(id) and skill_purchased(id).

signal skill_selected(skill_id: String)
signal skill_purchased(skill_id: String)

const BASE_NODE_RADIUS := 34.0
const BASE_GRID_SCALE  := Vector2(92.0, 82.0)
const MIN_ZOOM := 0.35
const MAX_ZOOM := 1.8

@export var pan_speed_keyboard: float = 480.0

var _camera_offset: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _panning: bool = false
## True once the user has panned / zoomed / pinched. Until then we keep the
## camera parked on the root node whenever the control is (re)sized, so the shop
## always opens centred on "Unlock UI" even if the first layout pass hadn't
## settled the control's size when _ready ran.
var _user_moved: bool = false
var _pressed_inside: bool = false
var _press_pos: Vector2
var _drag_start_offset: Vector2
var _moved_since_press: bool = false
var _press_hit_id: String = ""
var _hover_id: String = ""
var _selected_id: String = ""
const DRAG_THRESHOLD := 6.0

# Two-finger pinch tracking.
var _touch_points: Dictionary = {}   # index -> Vector2
var _pinch_start_dist: float = 0.0
var _pinch_start_zoom: float = 1.0

# Recommend-cycle state — the shop calls focus_on() with the next recommended
# skill id; we tween camera + zoom toward it and briefly pulse a highlight ring
# so the user's eye lands on the right node.
var _focus_tween: Tween = null
var _focus_pulse_id: String = ""
var _focus_pulse_t: float = 0.0
const FOCUS_ZOOM := 1.35
const FOCUS_PULSE_SECS := 1.6

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	_centre_on_root.call_deferred()

func _on_resized() -> void:
	# Keep the camera on the root until the user takes control. The Tree control
	# lives inside a Body HBox, so its real size often isn't known when _ready's
	# deferred centre runs — recentring on the first real resize fixes the
	# "opens off-target, snaps on touch" bug.
	if not _user_moved:
		_centre_on_root()

func _centre_on_root() -> void:
	_camera_offset = size * 0.5
	queue_redraw()

func _grid_scale() -> Vector2:
	return BASE_GRID_SCALE * _zoom

func _node_radius() -> float:
	return BASE_NODE_RADIUS * _zoom

func _process(delta: float) -> void:
	var pan = Vector2.ZERO
	# Keyboard pan polls Input directly, so guide_finger's set_input_as_handled()
	# can't gate it. Freeze it while the guide is pointing, or the tree slides out
	# from under the finger.
	if not Onboarding.is_active():
		if Input.is_action_pressed("right"): pan.x -= 1
		if Input.is_action_pressed("left"):  pan.x += 1
		if Input.is_action_pressed("up"):    pan.y += 1
		if Input.is_action_pressed("down"):  pan.y -= 1
	if pan != Vector2.ZERO:
		_camera_offset += pan * pan_speed_keyboard * delta
		_user_moved = true
		queue_redraw()
	# Focus pulse ring animation.
	if _focus_pulse_id != "":
		_focus_pulse_t += delta
		if _focus_pulse_t >= FOCUS_PULSE_SECS:
			_focus_pulse_id = ""
			_focus_pulse_t = 0.0
		queue_redraw()

func _world_pos(skill_id: String) -> Vector2:
	var p: Vector2 = SkillsDB.get_tree_pos(skill_id)
	return _camera_offset + p * _grid_scale()

## True if the node should be drawn / hit-testable right now.
## Rule: ROOT always visible. A node is revealed only when ALL of its direct
## prerequisites are purchased — so cross-branch skills stay hidden until the
## player has unlocked every required branch, and deep nodes stay hidden until
## the immediately-upstream path is fully cleared.
func _is_revealed(sid: String) -> bool:
	if Global.debug_toggles.get("unlock_all", false): return true
	if sid == SkillsDB.ROOT_ID: return true
	if SkillsDB.is_purchased(sid): return true
	var d = SkillsDB.SKILLS.get(sid, null)
	if d == null: return false
	var reqs: Array = d.get("requires", [])
	if reqs.is_empty(): return true
	# All prereqs must be purchased for the node to be visible.
	for r in reqs:
		if not SkillsDB.is_purchased(r):
			return false
	return true

func _zoom_around(new_zoom: float, focus: Vector2) -> void:
	new_zoom = clamp(new_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, _zoom): return
	_user_moved = true
	# Keep the point under focus stationary in local space.
	var world = (focus - _camera_offset) / _zoom
	_zoom = new_zoom
	_camera_offset = focus - world * _zoom
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_pressed_inside = true
				_panning = true
				_press_pos = event.position
				_drag_start_offset = _camera_offset
				_moved_since_press = false
				_press_hit_id = _hit_test(event.position)
			else:
				if _pressed_inside and not _moved_since_press and _press_hit_id != "":
					_selected_id = _press_hit_id
					emit_signal("skill_selected", _press_hit_id)
				_pressed_inside = false
				_panning = false
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if event.shift_pressed:
				_camera_offset.x += 80
				_user_moved = true
				queue_redraw()
			else:
				_zoom_around(_zoom * 1.12, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if event.shift_pressed:
				_camera_offset.x -= 80
				_user_moved = true
				queue_redraw()
			else:
				_zoom_around(_zoom / 1.12, event.position)
	elif event is InputEventMouseMotion:
		if _panning:
			var delta = event.position - _press_pos
			if not _moved_since_press and delta.length() > DRAG_THRESHOLD:
				_moved_since_press = true
				_user_moved = true
			if _moved_since_press:
				_camera_offset = _drag_start_offset + delta
				queue_redraw()
		var prev_hover = _hover_id
		_hover_id = _hit_test(event.position)
		if prev_hover != _hover_id:
			queue_redraw()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
			if _touch_points.size() == 1:
				_pressed_inside = true
				_panning = true
				_press_pos = event.position
				_drag_start_offset = _camera_offset
				_moved_since_press = false
				_press_hit_id = _hit_test(event.position)
			elif _touch_points.size() == 2:
				# Enter pinch mode, cancel any pending tap.
				_panning = false
				_press_hit_id = ""
				var pts = _touch_points.values()
				_pinch_start_dist = max(1.0, pts[0].distance_to(pts[1]))
				_pinch_start_zoom = _zoom
		else:
			if _touch_points.has(event.index):
				_touch_points.erase(event.index)
			if _touch_points.size() < 2:
				_pinch_start_dist = 0.0
			if _touch_points.size() == 0:
				if _pressed_inside and not _moved_since_press and _press_hit_id != "":
					_selected_id = _press_hit_id
					emit_signal("skill_selected", _press_hit_id)
				_pressed_inside = false
				_panning = false
				queue_redraw()
	elif event is InputEventScreenDrag:
		if _touch_points.has(event.index):
			_touch_points[event.index] = event.position
		if _touch_points.size() >= 2 and _pinch_start_dist > 0.0:
			var pts = _touch_points.values()
			var dist = max(1.0, pts[0].distance_to(pts[1]))
			var mid = (pts[0] + pts[1]) * 0.5
			_zoom_around(_pinch_start_zoom * (dist / _pinch_start_dist), mid)
		elif _panning:
			var delta = event.position - _press_pos
			if not _moved_since_press and delta.length() > DRAG_THRESHOLD:
				_moved_since_press = true
				_user_moved = true
			if _moved_since_press:
				_camera_offset = _drag_start_offset + delta
				queue_redraw()

func _hit_test(local_pos: Vector2) -> String:
	var r = _node_radius() + 2
	for sid in SkillsDB.SKILLS.keys():
		if not _is_revealed(sid): continue
		var wp = _world_pos(sid)
		if local_pos.distance_to(wp) <= r:
			return sid
	return ""

func set_selected(sid: String) -> void:
	_selected_id = sid
	queue_redraw()

func selected_id() -> String:
	return _selected_id

## ─── PUBLIC GEOMETRY (used by guide_finger.gd via onboarding.gd) ────────────

## Viewport-space centre of a node, so an overlay can point at it.
func screen_pos_of(sid: String) -> Vector2:
	return global_position + _world_pos(sid)

## Current on-screen node radius, including zoom.
func node_screen_radius() -> float:
	return _node_radius()

## Whether a node is currently drawn (its upstream path is purchased).
func is_revealed(sid: String) -> bool:
	return _is_revealed(sid)

## Tween camera + zoom so `sid` lands in the centre of the view. Also emits
## skill_selected and starts a highlight pulse so the user's eye is drawn to it.
func focus_on(sid: String) -> void:
	if not SkillsDB.SKILLS.has(sid): return
	_user_moved = true
	var target_zoom: float = clamp(FOCUS_ZOOM, MIN_ZOOM, MAX_ZOOM)
	# Compute the offset that puts sid at the panel centre at the target zoom.
	var world: Vector2 = SkillsDB.get_tree_pos(sid)
	var grid: Vector2 = BASE_GRID_SCALE * target_zoom
	var target_offset: Vector2 = size * 0.5 - world * grid
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.tween_method(_apply_zoom_scalar, _zoom, target_zoom, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(self, "_camera_offset", target_offset, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_selected_id = sid
	_focus_pulse_id = sid
	_focus_pulse_t = 0.0
	emit_signal("skill_selected", sid)
	queue_redraw()

func _apply_zoom_scalar(v: float) -> void:
	_zoom = v
	queue_redraw()

func _draw() -> void:
	_draw_grid()
	_draw_bg_hint()

	var polished := Global.is_unlocked("skill_tree_polish") or Global.is_unlocked("main_menu_extras")
	var phase = Time.get_ticks_msec() * 0.001

	# Edges first (under nodes). Only draw edges whose destination is revealed
	# so unrevealed branches don't leak visual info.
	for sid in SkillsDB.SKILLS.keys():
		if not _is_revealed(sid): continue
		var d = SkillsDB.SKILLS[sid]
		var to_p = _world_pos(sid)
		for r in d.get("requires", []):
			if not SkillsDB.SKILLS.has(r): continue
			if not _is_revealed(r): continue
			var from_p = _world_pos(r)
			var _ua2: bool = Global.debug_toggles.get("unlock_all", false)
			var purchased_to = SkillsDB.is_purchased(sid) or _ua2
			var purchased_from = SkillsDB.is_purchased(r) or _ua2
			var col = Color(0.30, 0.25, 0.18, 0.7)
			var w = 4.0
			if purchased_from and purchased_to:
				col = Color(0.95, 0.78, 0.30); w = 6.0
			elif purchased_from:
				col = Color(0.55, 0.50, 0.40, 0.95); w = 5.0
			if polished:
				_draw_curved_edge(from_p, to_p, col, w, purchased_from and purchased_to, phase)
			else:
				draw_line(from_p, to_p, col, w, true)

	# Nodes
	for sid in SkillsDB.SKILLS.keys():
		if not _is_revealed(sid): continue
		_draw_node(sid)

	# Focus pulse ring (drawn on top of the highlighted node).
	_draw_focus_pulse()

	# "There is more" ghost pips at the far end of edges going to hidden nodes.
	for sid in SkillsDB.SKILLS.keys():
		if not _is_revealed(sid): continue
		var d = SkillsDB.SKILLS[sid]
		if not SkillsDB.is_purchased(sid): continue
		for other in SkillsDB.SKILLS.keys():
			if _is_revealed(other): continue
			var od = SkillsDB.SKILLS[other]
			if not od.get("requires", []).has(sid): continue
			var from_p = _world_pos(sid)
			var to_p = _world_pos(other)
			var dir = (to_p - from_p).normalized()
			var pip_pos = from_p + dir * (_node_radius() + 22.0)
			draw_circle(pip_pos, 6.0 * _zoom, Color(0.55, 0.50, 0.40, 0.75))
			var font = ThemeDB.fallback_font
			var fs = int(13 * _zoom)
			draw_string(font, pip_pos + Vector2(-5, 5) * _zoom, "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.15, 0.10, 0.05))

func _draw_curved_edge(from_p: Vector2, to_p: Vector2, col: Color, w: float, animated: bool, phase: float) -> void:
	# Cubic bezier with control points offset perpendicular to the segment.
	var seg = to_p - from_p
	var perp = Vector2(-seg.y, seg.x).normalized()
	var bend = min(seg.length() * 0.18, 60.0)
	var c1 = from_p + seg * 0.33 + perp * bend
	var c2 = from_p + seg * 0.66 + perp * bend
	var pts: PackedVector2Array = PackedVector2Array()
	var steps := 22
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var it = 1.0 - t
		var p = it*it*it*from_p + 3.0*it*it*t*c1 + 3.0*it*t*t*c2 + t*t*t*to_p
		pts.append(p)
	# Glow underlay.
	var glow = col
	glow.a *= 0.25
	draw_polyline(pts, glow, w + 6.0, true)
	# Main stroke.
	draw_polyline(pts, col, w, true)
	# Animated dashed pulse on active edges.
	if animated:
		var dash_col = Color(1, 1, 1, 0.65)
		var count = pts.size() - 1
		for i in range(count):
			var t = float(i) / float(count)
			var v = fmod(t + phase * 0.35, 1.0)
			if v < 0.12:
				draw_line(pts[i], pts[i + 1], dash_col, w * 0.55, true)

func _draw_grid() -> void:
	var step = 60.0 * _zoom
	if step < 20.0: step = 20.0
	var col = Color(0, 0, 0, 0.06)
	var sz = size
	var ox = fposmod(_camera_offset.x, step)
	var oy = fposmod(_camera_offset.y, step)
	var x = ox
	while x < sz.x:
		draw_line(Vector2(x, 0), Vector2(x, sz.y), col, 1.0)
		x += step
	var y = oy
	while y < sz.y:
		draw_line(Vector2(0, y), Vector2(sz.x, y), col, 1.0)
		y += step

func _draw_node(sid: String) -> void:
	var d = SkillsDB.SKILLS[sid]
	var p = _world_pos(sid)
	if p.x < -160 or p.x > size.x + 160 or p.y < -160 or p.y > size.y + 160:
		return
	var branch_col: Color = SkillsDB.get_branch_color(d.get("branch", "ui"))
	var unlock_all: bool = Global.debug_toggles.get("unlock_all", false)
	var purchased := SkillsDB.is_purchased(sid) or unlock_all
	var prereq := SkillsDB.prereqs_met(sid) or unlock_all
	var affordable := SkillsDB.can_afford(sid) or unlock_all

	var alpha := 1.0
	var polished := Global.is_unlocked("main_menu_extras")

	var r := _node_radius()
	if sid == _hover_id: r += 4
	if sid == _selected_id: r += 2

	# Shadow
	draw_circle(p + Vector2(0, 4), r + (2.0 if polished else 0.0), Color(0, 0, 0, 0.25 * alpha))

	# Body
	var bg: Color
	if purchased:
		bg = branch_col
	elif prereq:
		if affordable:
			bg = branch_col.lerp(Color.WHITE, 0.55)
		else:
			bg = Color(0.85, 0.80, 0.70)
	else:
		bg = Color(0.40, 0.36, 0.30)
	bg.a *= alpha
	draw_circle(p, r, bg)

	if polished:
		draw_circle(p - Vector2(r * 0.35, r * 0.4), r * 0.32, Color(1, 1, 1, 0.35 * alpha))
		draw_arc(p, r * 0.72, 0.0, TAU, 40, Color(1, 1, 1, 0.35 * alpha), 2.0, true)

	# Ring
	var ring_col := Color(0.18, 0.14, 0.10, alpha)
	if sid == _selected_id: ring_col = Color(1, 1, 1, alpha)
	draw_arc(p, r, 0.0, TAU, 64, ring_col, 3.5, true)

	# Icon label — always dark ink so it stays readable on selected/light backgrounds.
	var icon: String = d.get("icon", "?")
	var font = ThemeDB.fallback_font
	var fs := int(16 * _zoom)
	var ts = font.get_string_size(icon, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var icon_col := Color(0.12, 0.08, 0.06, alpha)
	draw_string(font, p - ts * 0.5 + Vector2(0, ts.y * 0.40), icon,
		HORIZONTAL_ALIGNMENT_CENTER, -1, fs, icon_col)

	# Label below
	var name_str: String = d.get("name", sid)
	var lfs := int(16 * _zoom)
	var lts = font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, lfs)
	var pad := Vector2(8, 4)
	var rect = Rect2(p + Vector2(-lts.x * 0.5 - pad.x, r + 8 - pad.y),
					 Vector2(lts.x + pad.x * 2, lts.y + pad.y * 2))
	draw_rect(rect, Color(1, 0.95, 0.85, 0.9), true)
	draw_rect(rect, Color(0.18, 0.14, 0.10, 0.6), false, 1.0)
	draw_string(font, p + Vector2(-lts.x * 0.5, r + 8 + lts.y * 0.85), name_str,
		HORIZONTAL_ALIGNMENT_CENTER, -1, lfs, Color(0.18, 0.14, 0.10))

	# Cost badge
	if not purchased:
		var cost = SkillsDB.compute_cost(sid)
		var cs := "%d ★" % cost
		var cfs := int(14 * _zoom)
		var cts = font.get_string_size(cs, HORIZONTAL_ALIGNMENT_CENTER, -1, cfs)
		var crect = Rect2(p + Vector2(-cts.x * 0.5 - 6, -r - cts.y - 12),
						  Vector2(cts.x + 12, cts.y + 6))
		var badge_col = Color(0.95, 0.78, 0.30) if affordable and prereq else Color(0.50, 0.45, 0.40)
		draw_rect(crect, badge_col, true)
		draw_rect(crect, Color(0.18, 0.14, 0.10), false, 1.5)
		draw_string(font, p + Vector2(-cts.x * 0.5, -r - 8), cs,
			HORIZONTAL_ALIGNMENT_CENTER, -1, cfs, Color(0.18, 0.14, 0.10))

## Faint "how to navigate" chips drawn behind the grid so first-time users
## know they can drag / pinch / scroll. Text sits in the bottom-left corner
## and stays static across camera pans so it reads like screen-space UI.
func _draw_bg_hint() -> void:
	var font = ThemeDB.fallback_font
	# Detect touch capability so we prefer the pinch phrasing there. Godot's
	# DisplayServer exposes `is_touchscreen_available` on mobile / windows-touch.
	var touch := false
	if DisplayServer.has_method("is_touchscreen_available"):
		touch = DisplayServer.is_touchscreen_available()
	var lines: Array
	if touch:
		lines = [
			"drag  ·  to pan",
			"pinch  ·  to zoom",
			"tap a node  ·  to select",
		]
	else:
		lines = [
			"drag  ·  to pan",
			"scroll  ·  to zoom",
			"click a node  ·  to select",
		]
	var fs := 18
	var pad := Vector2(14, 10)
	var line_h := 22
	var block_h: float = float(line_h * lines.size()) + pad.y * 2.0
	var block_w: float = 260.0
	var origin := Vector2(18, size.y - block_h - 18)
	# Soft rounded background so the hint reads without competing with the grid.
	var bg_rect := Rect2(origin, Vector2(block_w, block_h))
	draw_rect(bg_rect, Color(1.0, 0.96, 0.85, 0.35), true)
	draw_rect(bg_rect, Color(0.30, 0.22, 0.14, 0.20), false, 1.0)
	for i in range(lines.size()):
		var y := origin.y + pad.y + line_h * (i + 1) - 6
		draw_string(font, Vector2(origin.x + pad.x, y), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.20, 0.14, 0.08, 0.55))

## Expanding, fading ring drawn around the currently-focused recommend target
## so the user can spot it after the camera tween lands.
func _draw_focus_pulse() -> void:
	if _focus_pulse_id == "": return
	if not SkillsDB.SKILLS.has(_focus_pulse_id): return
	var p: Vector2 = _world_pos(_focus_pulse_id)
	var t: float = _focus_pulse_t / FOCUS_PULSE_SECS
	# Two overlapping rings on staggered phases so the pulse reads as ongoing
	# rather than a single quick flash.
	for phase in [0.0, 0.5]:
		var pt: float = fmod(t + phase, 1.0)
		var base_r: float = _node_radius() * 1.15
		var ring_r: float = base_r + pt * 90.0 * _zoom
		var alpha: float = 0.85 * (1.0 - pt)
		draw_arc(p, ring_r, 0.0, TAU, 48,
			Color(1.0, 0.85, 0.30, alpha), 4.0 * _zoom, true)
