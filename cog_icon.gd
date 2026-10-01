extends Control

## Chunky polygon cog. Drop-in child of a Button to render an icon that scales
## without relying on emoji fonts. Draws with rounded trapezoid teeth, an
## inner rim highlight, a hub ring, and a cross screw-slot in the center.

@export var color: Color = Color(0.18, 0.14, 0.10)
@export var hub_color: Color = Color(1.0, 0.95, 0.85)
@export var accent_color: Color = Color(0.35, 0.28, 0.20)
@export var teeth: int = 8
@export var tooth_width: float = 0.42  # fraction of the angular slice occupied by a tooth
@export var slowly_spin: bool = true
@export var spin_speed: float = 0.35   # radians per second

var _spin: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(slowly_spin)

func _process(delta: float) -> void:
	_spin += delta * spin_speed
	queue_redraw()

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r_out: float = min(size.x, size.y) * 0.46
	var r_mid: float = r_out * 0.78   # body radius (teeth root)
	var r_hub: float = r_out * 0.42
	var r_hole: float = r_out * 0.16

	# ── TEETH ── trapezoids stepped around the rim.
	var slice: float = TAU / float(teeth)
	var half: float = slice * tooth_width * 0.5
	for i in range(teeth):
		var a: float = _spin + slice * float(i)
		var p1: Vector2 = c + Vector2(cos(a - half), sin(a - half)) * r_mid
		var p2: Vector2 = c + Vector2(cos(a + half), sin(a + half)) * r_mid
		var p3: Vector2 = c + Vector2(cos(a + half * 0.7), sin(a + half * 0.7)) * r_out
		var p4: Vector2 = c + Vector2(cos(a - half * 0.7), sin(a - half * 0.7)) * r_out
		var tooth := PackedVector2Array([p1, p2, p3, p4])
		draw_colored_polygon(tooth, color)

	# ── BODY DISC ──
	draw_circle(c, r_mid, color)
	# Inner rim accent — a slightly lighter ring inside the body.
	draw_arc(c, r_mid * 0.88, 0.0, TAU, 48, accent_color, 3.0, true)

	# ── HUB ──
	draw_circle(c, r_hub, hub_color)
	draw_arc(c, r_hub, 0.0, TAU, 48, color, 2.5, true)

	# ── CENTER HOLE / SCREW SLOT ──
	draw_circle(c, r_hole, color)
	# Cross slot — two thin bars rotated with the cog.
	var slot_len: float = r_hub * 0.65
	var slot_thk: float = r_out * 0.06
	for k in range(2):
		var ang: float = _spin + float(k) * PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		var perp := Vector2(-dir.y, dir.x)
		var s1: Vector2 = c + dir * slot_len - perp * slot_thk
		var s2: Vector2 = c + dir * slot_len + perp * slot_thk
		var s3: Vector2 = c - dir * slot_len + perp * slot_thk
		var s4: Vector2 = c - dir * slot_len - perp * slot_thk
		draw_colored_polygon(PackedVector2Array([s1, s2, s3, s4]), hub_color)
