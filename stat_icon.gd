extends Control

## Small polygon icon used next to death-screen stat rows. Consistent visual
## language: dark ink strokes / fills on a lighter background so they read at
## a glance without needing a texture asset.

enum Kind { STAR, FLAG, HASH, TROPHY, SKULL, REDO, HOME, BAG, DOOR, FIRE, COPY, DICE }

@export var kind: int = Kind.STAR
@export var color: Color = Color(0.15, 0.10, 0.06)
@export var accent: Color = Color(0.95, 0.78, 0.30)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var s: float = min(size.x, size.y) * 0.44
	match kind:
		Kind.STAR:   _draw_star(c, s)
		Kind.FLAG:   _draw_flag(c, s)
		Kind.HASH:   _draw_hash(c, s)
		Kind.TROPHY: _draw_trophy(c, s)
		Kind.SKULL:  _draw_skull(c, s)
		Kind.REDO:   _draw_redo(c, s)
		Kind.HOME:   _draw_home(c, s)
		Kind.BAG:    _draw_bag(c, s)
		Kind.DOOR:   _draw_door(c, s)
		Kind.FIRE:   _draw_fire(c, s)
		Kind.COPY:   _draw_copy(c, s)
		Kind.DICE:   _draw_dice(c, s)

func _draw_star(c: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	var outer := s
	var inner := s * 0.42
	for i in range(10):
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		var r := outer if (i % 2) == 0 else inner
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, accent)
	# Ink outline.
	pts.append(pts[0])
	draw_polyline(pts, color, 2.0, true)

func _draw_flag(c: Vector2, s: float) -> void:
	# Vertical pole with a triangular pennant — reads as "distance / finish".
	var pole_x := c.x - s * 0.5
	draw_line(Vector2(pole_x, c.y - s), Vector2(pole_x, c.y + s * 0.9), color, 3.0)
	var pennant := PackedVector2Array([
		Vector2(pole_x, c.y - s + 2),
		Vector2(pole_x + s * 1.3, c.y - s * 0.4),
		Vector2(pole_x, c.y + s * 0.05),
	])
	draw_colored_polygon(pennant, accent)
	# Foot base.
	draw_circle(Vector2(pole_x, c.y + s * 0.9), 3.0, color)

func _draw_hash(c: Vector2, s: float) -> void:
	# Two horizontal + two vertical bars, classic # for "seed code".
	var h := s * 0.9
	var t := s * 0.18
	# Verticals.
	draw_line(c + Vector2(-h * 0.35, -h), c + Vector2(-h * 0.35, h), color, t)
	draw_line(c + Vector2( h * 0.35, -h), c + Vector2( h * 0.35, h), color, t)
	# Horizontals (slightly tilted for a hand-drawn feel).
	draw_line(c + Vector2(-h, -h * 0.35), c + Vector2(h, -h * 0.35 - 3), color, t)
	draw_line(c + Vector2(-h,  h * 0.35), c + Vector2(h,  h * 0.35 - 3), color, t)

func _draw_trophy(c: Vector2, s: float) -> void:
	# Cup body.
	var cup := Rect2(c + Vector2(-s * 0.55, -s * 0.9), Vector2(s * 1.1, s * 1.2))
	draw_rect(cup, accent, true)
	draw_rect(cup, color, false, 2.0)
	# Handles.
	draw_arc(c + Vector2(-s * 0.55, -s * 0.4), s * 0.35, PI * 0.5, PI * 1.5, 12, color, 2.5, true)
	draw_arc(c + Vector2( s * 0.55, -s * 0.4), s * 0.35, -PI * 0.5, PI * 0.5, 12, color, 2.5, true)
	# Stem + base.
	draw_rect(Rect2(c + Vector2(-s * 0.14, s * 0.30), Vector2(s * 0.28, s * 0.32)), color, true)
	draw_rect(Rect2(c + Vector2(-s * 0.6,  s * 0.62), Vector2(s * 1.2,  s * 0.22)), color, true)

func _draw_skull(c: Vector2, s: float) -> void:
	# Head.
	draw_circle(c + Vector2(0, -s * 0.15), s * 0.85, accent)
	# Jaw.
	var jaw := Rect2(c + Vector2(-s * 0.55, s * 0.15), Vector2(s * 1.1, s * 0.5))
	draw_rect(jaw, accent, true)
	# Eye sockets.
	draw_circle(c + Vector2(-s * 0.35, -s * 0.1), s * 0.22, color)
	draw_circle(c + Vector2( s * 0.35, -s * 0.1), s * 0.22, color)
	# Nose triangle.
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, s * 0.05),
		c + Vector2(-s * 0.12, s * 0.28),
		c + Vector2( s * 0.12, s * 0.28),
	]), color)
	# Teeth: three vertical bars in the jaw.
	for i in range(3):
		var x := -s * 0.28 + float(i) * s * 0.28
		draw_line(c + Vector2(x, s * 0.32), c + Vector2(x, s * 0.6), color, 2.0)

func _draw_redo(c: Vector2, s: float) -> void:
	# Circular arrow (retry).
	draw_arc(c, s * 0.75, -PI * 0.25, PI * 1.5, 32, color, 4.0, true)
	# Arrowhead at the arc terminus.
	var end_ang := -PI * 0.25
	var tip := c + Vector2(cos(end_ang), sin(end_ang)) * s * 0.75
	var head := PackedVector2Array([
		tip + Vector2(s * 0.25, -s * 0.1),
		tip + Vector2(-s * 0.05, -s * 0.35),
		tip + Vector2(-s * 0.05,  s * 0.15),
	])
	draw_colored_polygon(head, color)

func _draw_home(c: Vector2, s: float) -> void:
	# Roof triangle.
	var roof := PackedVector2Array([
		c + Vector2(-s, 0),
		c + Vector2(0, -s * 0.9),
		c + Vector2(s, 0),
	])
	draw_colored_polygon(roof, accent)
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2]]), color, 2.0, true)
	# Body.
	var body := Rect2(c + Vector2(-s * 0.75, 0), Vector2(s * 1.5, s * 0.85))
	draw_rect(body, accent, true)
	draw_rect(body, color, false, 2.0)
	# Door.
	draw_rect(Rect2(c + Vector2(-s * 0.2, s * 0.25), Vector2(s * 0.4, s * 0.6)), color, true)

func _draw_bag(c: Vector2, s: float) -> void:
	# Shop / coin bag: rounded rect body with a tie at the top.
	var body := Rect2(c + Vector2(-s * 0.75, -s * 0.35), Vector2(s * 1.5, s * 1.2))
	draw_rect(body, accent, true)
	draw_rect(body, color, false, 2.0)
	# Tie: two little bumps.
	draw_line(c + Vector2(-s * 0.4, -s * 0.35), c + Vector2(-s * 0.15, -s * 0.6), color, 3.0)
	draw_line(c + Vector2( s * 0.4, -s * 0.35), c + Vector2( s * 0.15, -s * 0.6), color, 3.0)
	# Coin.
	draw_circle(c + Vector2(0, s * 0.2), s * 0.3, color)
	draw_string(ThemeDB.fallback_font, c + Vector2(-s * 0.15, s * 0.32), "★",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.6), accent)

func _draw_door(c: Vector2, s: float) -> void:
	# Exit door: rectangle with a small round knob.
	var door := Rect2(c + Vector2(-s * 0.6, -s * 0.95), Vector2(s * 1.2, s * 1.9))
	draw_rect(door, accent, true)
	draw_rect(door, color, false, 2.0)
	draw_circle(c + Vector2(s * 0.3, 0), s * 0.12, color)

func _draw_fire(c: Vector2, s: float) -> void:
	# Flame: two teardrop lobes stacked, orange outer + yellow inner.
	var outer := PackedVector2Array([
		c + Vector2(0, -s * 1.05),
		c + Vector2( s * 0.55, -s * 0.35),
		c + Vector2( s * 0.75,  s * 0.35),
		c + Vector2( s * 0.35,  s * 0.85),
		c + Vector2(-s * 0.35,  s * 0.85),
		c + Vector2(-s * 0.75,  s * 0.35),
		c + Vector2(-s * 0.55, -s * 0.35),
	])
	draw_colored_polygon(outer, Color(1.00, 0.45, 0.15))
	var inner := PackedVector2Array([
		c + Vector2(0, -s * 0.55),
		c + Vector2( s * 0.35,  s * 0.05),
		c + Vector2( s * 0.20,  s * 0.55),
		c + Vector2(-s * 0.20,  s * 0.55),
		c + Vector2(-s * 0.35,  s * 0.05),
	])
	draw_colored_polygon(inner, Color(1.00, 0.90, 0.30))
	# Outline.
	var outline := PackedVector2Array(outer)
	outline.append(outer[0])
	draw_polyline(outline, color, 2.0, true)

func _draw_copy(c: Vector2, s: float) -> void:
	# Two overlapping rounded rectangles suggest "copy to clipboard".
	var back := Rect2(c + Vector2(-s * 0.75, -s * 0.55), Vector2(s * 1.15, s * 1.35))
	draw_rect(back, accent, true)
	draw_rect(back, color, false, 2.0)
	var front := Rect2(c + Vector2(-s * 0.35, -s * 0.2), Vector2(s * 1.15, s * 1.35))
	draw_rect(front, Color(1.0, 1.0, 1.0, 0.85), true)
	draw_rect(front, color, false, 2.0)
	# Two content lines on the front sheet.
	for i in range(2):
		var y := front.position.y + s * 0.4 + float(i) * s * 0.35
		draw_line(Vector2(front.position.x + s * 0.15, y),
				  Vector2(front.position.x + front.size.x - s * 0.15, y),
				  color, 2.0)

func _draw_dice(c: Vector2, s: float) -> void:
	# Die: square with 5-pip face.
	var body := Rect2(c + Vector2(-s * 0.9, -s * 0.9), Vector2(s * 1.8, s * 1.8))
	draw_rect(body, accent, true)
	draw_rect(body, color, false, 2.5)
	var r := s * 0.13
	# Corner pips + center.
	draw_circle(c + Vector2(-s * 0.5, -s * 0.5), r, color)
	draw_circle(c + Vector2( s * 0.5, -s * 0.5), r, color)
	draw_circle(c + Vector2(-s * 0.5,  s * 0.5), r, color)
	draw_circle(c + Vector2( s * 0.5,  s * 0.5), r, color)
	draw_circle(c,                                r, color)
