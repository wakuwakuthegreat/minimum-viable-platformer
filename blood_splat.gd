extends Node
class_name BloodSplat

## Spawns a blood-particle burst at `pos`, parented to `parent`.
## No-op if the player hasn't bought the "blood_splats" skill.
##
## Circular burst shape + optional velocity trail (toggleable in settings).
## Also stamps a persistent mark onto the BloodCanvas layer when "blood_marks" is unlocked.

## Built once and shared by every splat — same fixed colors every call, so
## there's no reason to allocate + rebuild these on every single enemy death.
static var _burst_ramp: Gradient = null
static var _trail_ramp: Gradient = null

static func _get_burst_ramp() -> Gradient:
	if _burst_ramp == null:
		_burst_ramp = Gradient.new()
		_burst_ramp.set_color(0, Color(0.85, 0.12, 0.12, 1.0))
		_burst_ramp.add_point(0.55, Color(0.55, 0.06, 0.06, 1.0))
		_burst_ramp.add_point(1.0,  Color(0.28, 0.04, 0.04, 0.0))
	return _burst_ramp

static func _get_trail_ramp() -> Gradient:
	if _trail_ramp == null:
		_trail_ramp = Gradient.new()
		_trail_ramp.set_color(0, Color(0.75, 0.10, 0.10, 0.9))
		_trail_ramp.add_point(1.0,  Color(0.30, 0.04, 0.04, 0.0))
	return _trail_ramp

static func apply(parent: Node, pos: Vector2, velocity: Vector2 = Vector2.ZERO) -> void:
	if not Global.is_unlocked("blood_splats"): return
	if parent == null or not parent.is_inside_tree(): return

	# Persistent stain on the level canvas — only when there is actual ground
	# beneath the impact within ~200 px. Mid-air kills leave no lasting mark.
	if Global.is_unlocked("blood_marks"):
		var canvas = parent.get_tree().get_first_node_in_group("blood_canvas")
		if canvas and canvas.has_method("add_mark"):
			var world_2d = parent.get_world_2d()
			if world_2d:
				var space = world_2d.direct_space_state
				var query := PhysicsRayQueryParameters2D.create(pos, pos + Vector2(0, 220))
				query.collision_mask = 1  # floor bodies
				var hit = space.intersect_ray(query)
				if hit and hit.has("position"):
					canvas.add_mark(hit.position, velocity)

	# ── Main burst (circular emission) ───────────────────────────────────────
	var p := CPUParticles2D.new()
	p.texture = Global.get_circle_texture()
	p.emitting = true
	p.one_shot = true
	p.amount = 32
	p.lifetime = 0.78
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 5.0
	p.spread = 65.0
	if velocity.length_squared() > 1.0:
		p.direction = -velocity.normalized()
	else:
		p.direction = Vector2(0, -1)
	p.gravity = Vector2(0, 900)
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 540.0
	p.scale_amount_min = 0.06   # 4–14 px droplets
	p.scale_amount_max = 0.22
	p.damping_min = 10.0
	p.damping_max = 26.0
	p.color = Color(0.78, 0.10, 0.10)
	p.color_ramp = _get_burst_ramp()

	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)

	# ── Tight spurt (fast narrow plume for wet impact feel) ──────────────────
	var spurt := CPUParticles2D.new()
	spurt.texture = Global.get_circle_texture()
	spurt.emitting = true
	spurt.one_shot = true
	spurt.amount = 12
	spurt.lifetime = 0.45
	spurt.explosiveness = 1.0
	spurt.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	spurt.emission_sphere_radius = 3.0
	spurt.spread = 22.0
	spurt.direction = p.direction
	spurt.gravity = Vector2(0, 600)
	spurt.initial_velocity_min = 500.0
	spurt.initial_velocity_max = 840.0
	spurt.scale_amount_min = 0.08
	spurt.scale_amount_max = 0.16
	spurt.color = Color(0.90, 0.15, 0.15)
	parent.add_child(spurt)
	spurt.global_position = pos
	spurt.finished.connect(spurt.queue_free)

	# ── Velocity trail (optional, disabled for performance via settings) ──────
	if Global.settings_cfg.get("blood_trail", true):
		var trail := CPUParticles2D.new()
		trail.texture = Global.get_circle_texture()
		trail.emitting = true
		trail.one_shot = true
		trail.amount = 18
		trail.lifetime = 0.9
		trail.explosiveness = 0.65
		trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		trail.emission_sphere_radius = 3.0
		trail.spread = 18.0
		# Trail drifts IN the direction of velocity (blood flung forward).
		if velocity.length_squared() > 1.0:
			trail.direction = velocity.normalized()
		else:
			trail.direction = Vector2(0, 1)
		trail.gravity = Vector2(0, 380)
		trail.initial_velocity_min = 70.0
		trail.initial_velocity_max = 220.0
		trail.scale_amount_min = 0.05
		trail.scale_amount_max = 0.19
		trail.color = Color(0.72, 0.08, 0.08, 0.8)
		trail.color_ramp = _get_trail_ramp()
		parent.add_child(trail)
		trail.global_position = pos
		trail.finished.connect(trail.queue_free)
