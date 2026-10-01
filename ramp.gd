extends StaticBody2D
class_name RampObject

@export var ramp_type: String = "up" # "up" (/) or "down" (\)
@export var base_size: Vector2 = Vector2(128, 128)

func _ready() -> void:
	update_ramp()

func update_ramp() -> void:
	var points = PackedVector2Array()
	if ramp_type == "up":
		# / Ramp
		points.append(Vector2(-base_size.x/2, base_size.y/2))
		points.append(Vector2(base_size.x/2, -base_size.y/2))
		points.append(Vector2(base_size.x/2, base_size.y/2))
	else:
		# \ Ramp
		points.append(Vector2(-base_size.x/2, -base_size.y/2))
		points.append(Vector2(base_size.x/2, base_size.y/2))
		points.append(Vector2(-base_size.x/2, base_size.y/2))
		
	var coll = $CollisionPolygon2D
	if coll:
		coll.polygon = points
	queue_redraw()

func _draw() -> void:
	var points = PackedVector2Array()
	if ramp_type == "up":
		points.append(Vector2(-base_size.x/2, base_size.y/2))
		points.append(Vector2(base_size.x/2, -base_size.y/2))
		points.append(Vector2(base_size.x/2, base_size.y/2))
	else:
		points.append(Vector2(-base_size.x/2, -base_size.y/2))
		points.append(Vector2(base_size.x/2, base_size.y/2))
		points.append(Vector2(-base_size.x/2, base_size.y/2))
	
	var base_stone := Color(0.33, 0.31, 0.28)
	var seam_col   := Color(0.24, 0.22, 0.20)
	var hi_col     := Color(0.62, 0.58, 0.52)
	
	# Solid ramp body
	draw_polygon(points, PackedColorArray([base_stone]))

	# Border outline
	var outline = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, seam_col, 2.0, true)

	# Clean slope bevel highlight
	if ramp_type == "up":
		draw_line(Vector2(-base_size.x/2, base_size.y/2), Vector2(base_size.x/2, -base_size.y/2), hi_col, 3.0)
	else:
		draw_line(Vector2(-base_size.x/2, -base_size.y/2), Vector2(base_size.x/2, base_size.y/2), hi_col, 3.0)

func squash() -> void:
	# Simple visual squash feedback
	scale = Vector2(1.1, 0.9)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SPRING)
