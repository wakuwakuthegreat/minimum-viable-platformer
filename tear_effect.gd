## TearEffect — Modular death-by-tearing.
## Call TearEffect.apply() from any node's die() to shatter it into physics pieces.
## Suggested usage:
##   TearEffect.apply(self, Vector2(64, 96), Color(0.8, 0.5, 0.2), velocity)
##   TearEffect.apply(self, tear_size, tear_color, impact_vel, tear_hard_points)
class_name TearEffect

## Tear a node into 2–5 irregular RigidBody2D polygon pieces.
## node        : Node2D to tear from (hid immediately; caller should queue_free it)
## size        : bounding box of the visual in local px  e.g. Vector2(80, 110)
## base_color  : colour of the torn pieces
## impact_vel  : velocity at moment of death (pieces scatter outward from this)
## hard_points : Array[Vector2] local-space coords that bias the cut angles
static func apply(
		node: Node2D,
		size: Vector2,
		base_color: Color,
		impact_vel: Vector2 = Vector2.ZERO,
		hard_points: Array = [],
		tear_type: String = "default") -> void:

	var parent = node.get_parent()
	if not parent: return
	var world_pos = node.global_position
	var world_rot = node.global_rotation

	var piece_count = randi_range(2, 5)
	var half        = size * 0.5
	var base_poly   = PackedVector2Array()
	
	if tear_type == "circular":
		var radius = min(size.x, size.y) * 0.5
		var segments = 16
		for i in range(segments):
			var angle = i * 2.0 * PI / segments
			base_poly.append(Vector2(cos(angle), sin(angle)) * radius)
		base_poly = _jag_polygon(base_poly, 4.0)
	elif tear_type == "logs":
		base_poly = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2( half.x, -half.y),
			Vector2( half.x,  half.y),
			Vector2(-half.x,  half.y),
		])
	else: # default
		base_poly = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2( half.x, -half.y),
			Vector2( half.x,  half.y),
			Vector2(-half.x,  half.y),
		])
		base_poly = _jag_polygon(base_poly, 7.0)

	var pieces = _subdivide(base_poly, piece_count - 1, hard_points, tear_type)

	# Try to find texture from Sprite2D or AnimatedSprite2D
	var texture: Texture2D = null
	var sprite_node = null
	for child in node.get_children():
		if child is Sprite2D:
			texture = child.texture
			sprite_node = child
			break
		elif child is AnimatedSprite2D:
			if child.sprite_frames and child.sprite_frames.has_animation(child.animation):
				texture = child.sprite_frames.get_frame_texture(child.animation, child.frame)
				sprite_node = child
				break

	for raw_poly in pieces:
		var poly: PackedVector2Array = raw_poly
		if poly.size() < 3: continue
		var centre = _centroid(poly)

		var rb = RigidBody2D.new()
		rb.global_position = world_pos
		rb.global_rotation  = world_rot
		rb.gravity_scale    = 2.0
		rb.linear_damp      = 0.25
		rb.collision_layer  = 0   # pieces don't block game
		rb.collision_mask   = 1   # bounce off floor

		var cp = CollisionPolygon2D.new()
		cp.polygon = poly
		rb.add_child(cp)

		var vis = Polygon2D.new()
		vis.polygon = poly
		
		if texture and sprite_node:
			vis.texture = texture
			var uvs = PackedVector2Array()
			var tex_size = texture.get_size()
			for v in poly:
				# Map local vertex to texture coordinate space
				var local_pos = (v - sprite_node.position) / sprite_node.scale
				var uv = local_pos + tex_size / 2.0
				
				if sprite_node.get("flip_h"):
					uv.x = tex_size.x - uv.x
				if sprite_node.get("flip_v"):
					uv.y = tex_size.y - uv.y
					
				uvs.append(uv)
			vis.uv = uvs
		else:
			var v = randf_range(-0.08, 0.08)
			vis.color = Color(
				clampf(base_color.r + v, 0.0, 1.0),
				clampf(base_color.g + v, 0.0, 1.0),
				clampf(base_color.b + v, 0.0, 1.0),
				base_color.a)
		rb.add_child(vis)

		# Outward impulse
		var outward = centre.normalized() if centre.length() > 1.0 \
				else Vector2(randf_range(-1.0, 1.0), -0.5).normalized()
		rb.linear_velocity  = impact_vel * 0.35 \
				+ outward * randf_range(200.0, 520.0) \
				+ Vector2(0.0, randf_range(-280.0, -60.0))
		rb.angular_velocity = randf_range(-10.0, 10.0)

		# Tween fade once in scene tree
		var life = randf_range(1.2, 2.4)
		rb.tree_entered.connect(func():
			var tw = rb.create_tween()
			tw.tween_interval(life * 0.55)
			tw.tween_property(vis, "modulate:a", 0.0, life * 0.45)
			tw.tween_callback(rb.queue_free))

		parent.call_deferred("add_child", rb)

	# Hide original immediately (caller should queue_free after calling apply)
	node.call_deferred("hide")


## Recursively subdivide a polygon with (cuts) straight-line cuts.
static func _subdivide(poly: PackedVector2Array, cuts: int, hard_points: Array, tear_type: String) -> Array:
	var pool: Array = [poly]
	for _i in range(cuts):
		if pool.is_empty(): break
		pool.sort_custom(func(a, b): return _area(a) > _area(b))
		var target: PackedVector2Array = pool.pop_front()
		var split = _cut(target, hard_points, tear_type)
		pool.append_array(split)
	return pool


## Cut a polygon with a straight line.
static func _cut(poly: PackedVector2Array, hard_points: Array, tear_type: String) -> Array:
	var bounds = _bounds(poly)
	var c      = _centroid(poly)
	var angle  = randf_range(0.0, PI)
	
	if tear_type == "logs":
		angle = 0.0
		c.y = randf_range(bounds.position.y + bounds.size.y * 0.2, bounds.position.y + bounds.size.y * 0.8)
	else:
		c += Vector2(
			randf_range(-bounds.size.x * 0.22, bounds.size.x * 0.22),
			randf_range(-bounds.size.y * 0.22, bounds.size.y * 0.22))
		for hp in hard_points:
			if typeof(hp) != TYPE_VECTOR2: continue
			if Vector2(hp).distance_to(c) < max(bounds.size.x, bounds.size.y) * 0.65:
				angle = (Vector2(hp) - c).angle() + PI * 0.5
				break

	var big  = max(bounds.size.x, bounds.size.y) * 3.0
	var dir  = Vector2(cos(angle), sin(angle))
	var norm = Vector2(-dir.y, dir.x)

	var side_a = PackedVector2Array([
		c + dir * big + norm * big,
		c - dir * big + norm * big,
		c - dir * big,
		c + dir * big,
	])
	var side_b = PackedVector2Array([
		c + dir * big,
		c - dir * big,
		c - dir * big - norm * big,
		c + dir * big - norm * big,
	])

	var result: Array = []
	for p in Geometry2D.intersect_polygons(poly, side_a):
		if p.size() >= 3: result.append(p)
	for p in Geometry2D.intersect_polygons(poly, side_b):
		if p.size() >= 3: result.append(p)

	if result.is_empty(): return [poly]
	return result


## Add slight jagged offsets to edge mid-points for an organic feel.
static func _jag_polygon(poly: PackedVector2Array, amp: float = 8.0) -> PackedVector2Array:
	var out = PackedVector2Array()
	for i in range(poly.size()):
		var a = poly[i]
		var b = poly[(i + 1) % poly.size()]
		out.append(a)
		var mid  = (a + b) * 0.5
		var perp = (b - a).rotated(PI * 0.5).normalized()
		mid += perp * randf_range(-amp, amp)
		out.append(mid)
	return out

static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c = Vector2.ZERO
	for v in poly: c += v
	return c / float(poly.size())

static func _bounds(poly: PackedVector2Array) -> Rect2:
	var mn = poly[0]; var mx = poly[0]
	for v in poly: mn = mn.min(v); mx = mx.max(v)
	return Rect2(mn, mx - mn)

static func _area(poly: PackedVector2Array) -> float:
	var a = 0.0; var n = poly.size()
	for i in range(n):
		var j = (i + 1) % n
		a += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return absf(a) * 0.5
