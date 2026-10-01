extends PlatformerController2D

@export var run_speed: float = 600.0
@export var auto_acceleration: float = 280.0  # How fast auto-run momentum builds up (px/s^2)

# Resolved-once feature flags (cached at _ready for hot-loop reads)
var _use_sprite_player: bool = false
var _use_sprite_anims:  bool = false
var _use_juice:         bool = false
var _use_shake:         bool = false
var _use_zoom:          bool = false
var _use_tears:         bool = false
var _use_particles:     bool = false
var _use_outline:       bool = false
var _use_double_jump:   bool = false
var _use_sprint:        bool = false
var _use_wall_jump:     bool = false
var _use_motion_trail:  bool = false
var _use_footstep_dust: bool = false
var _use_impact_freeze: bool = false
var _use_hit_flash:     bool = false
var _use_near_miss:     bool = false
var _use_parry:         bool = false
var _use_coin_magnet:   bool = false
var _use_ghost_mode:    bool = false
var _use_cursed_camera: bool = false
var _use_backflip:      bool = false
var _use_rainbow_trail: bool = false

# ─── AUDIO ─────────────────────────────────────────────────────────────────

# Near-miss slow-mo bookkeeping. Cooldown gates back-to-back triggers so
# passing several enemies in a chain only fires one cinematic beat.
const NEAR_MISS_RADIUS := 140.0
const NEAR_MISS_COOLDOWN := 1.2
const NEAR_MISS_CHANCE := 0.30
var _near_miss_cd: float = 0.0
var _near_miss_active: Dictionary = {}
var _debug_canvas: Node2D

# ─── PERF: cached world lookups ────────────────────────────────────────
# Rebuilding group arrays via get_nodes_in_group() every frame causes GC
# churn (visible as random hitches, especially on the web export). We refresh
# a few times per second instead; gameplay logic doesn't need fresher data.
const GROUP_REFRESH_INTERVAL := 0.2
var _group_refresh_timer: float = 0.0
var _hazards_cache: Array = []
var _coins_cache: Array = []

# get_local_lowest_y() is called every physics frame; the result only changes
# when the player crosses into a new tile column, so cache it per column.
var _lowest_y_cache: float = -999999.0
var _lowest_y_cache_col: int = -999999999

# Dynamic-zoom world lookups (group scan / shape query) are throttled too —
# zoom transitions tween over ~0.5s, so 5Hz is plenty and far cheaper.
var _zoom_should_out: bool = false
var _zoom_query_timer: float = 0.0

func _refresh_group_caches(delta: float) -> void:
	_group_refresh_timer -= delta
	if _group_refresh_timer > 0.0:
		return
	_group_refresh_timer = GROUP_REFRESH_INTERVAL
	_hazards_cache = get_tree().get_nodes_in_group("hazards")
	_coins_cache = get_tree().get_nodes_in_group("coins")

func _resolve_flags() -> void:
	# When primitives is forced via debug, everything visual stays primitive.
	var primitives = Global.use_primitives
	_use_sprite_player = (not primitives) and Global.is_unlocked("player_sprite")
	_use_sprite_anims  = _use_sprite_player and Global.is_unlocked("sprite_animations")
	_use_juice         = Global.is_unlocked("juice_squash")
	_use_shake         = Global.is_unlocked("camera_shake")
	_use_zoom          = Global.is_unlocked("dynamic_zoom")
	_use_tears         = Global.is_unlocked("tear_effects")
	_use_particles     = Global.is_unlocked("particles")
	_use_outline       = _use_sprite_player and Global.is_unlocked("outline")
	_use_double_jump   = Global.is_unlocked("double_jump")
	_use_sprint        = Global.is_unlocked("sprint")
	_use_wall_jump     = Global.is_unlocked("wall_jump")
	_use_motion_trail  = Global.is_unlocked("motion_trail")
	_use_footstep_dust = Global.is_unlocked("footstep_dust")
	_use_impact_freeze = Global.is_unlocked("impact_freeze")
	_use_hit_flash     = Global.is_unlocked("hit_flash")
	_use_near_miss     = Global.is_unlocked("near_miss_slowmo")
	_use_parry         = Global.is_unlocked("parry_mechanic")
	_use_coin_magnet   = Global.is_unlocked("coin_magnet")
	_use_ghost_mode    = Global.is_unlocked("ghost_mode")
	_use_cursed_camera = Global.is_unlocked("cursed_camera")
	_use_backflip      = Global.is_unlocked("backflip_jumps") and _use_sprite_player
	_use_rainbow_trail = Global.is_unlocked("rainbow_trail") and _use_motion_trail

func _ready() -> void:
	super._ready()
	add_to_group("player")
	_debug_canvas = Node2D.new()
	_debug_canvas.z_index = 100
	add_child(_debug_canvas)
	_debug_canvas.draw.connect(_on_debug_draw)
	_resolve_flags()
	dust_particles.texture = Global.get_circle_texture()
	_auto_setup_sprite_frames()

	if _use_sprint:
		run_speed = 820.0
	if Global.is_unlocked("fast_mode") and bool(Global.settings_cfg.get("fast_mode", false)):
		run_speed *= 1.35
	maxSpeed = run_speed
	maxSpeedLock = run_speed

	# Gameplay-unlock wiring on the addon's existing fields.
	if _use_double_jump:
		jumps = 2
	if _use_wall_jump:
		wallJump = true
	# Dev "new jump" — a crunchier, less-floaty curve. Stronger gravity makes the
	# arc snappier; jumpHeight is retuned so the peak stays about the same
	# (peak ∝ jumpMagnitude²/gravityScale, and jumpMagnitude = 10·jumpHeight·gravityScale),
	# and a bigger descending factor makes the fall bite harder than the rise.
	if bool(Global.settings_cfg.get("use_new_jump", false)):
		gravityScale = 26.0
		jumpHeight = 4.6
		descendingGravityFactor = 1.7
		terminalVelocity = 1100.0
	if has_method("_updateData"):
		_updateData()

	_setup_sensors()
	_setup_motion_trail()
	_setup_footstep_dust()
	_apply_outline_material()
	
	Global.player = self

func _draw() -> void:
	var s := Vector2.ONE
	if anim:
		s = Vector2(abs(anim.scale.x), abs(anim.scale.y))

	# Primitive shape if we don't have the player sprite unlocked.
	if not _use_sprite_player:
		var w := 80.0 * s.x
		var h := 110.0 * s.y
		var half_w := w * 0.5
		var half_h := h * 0.5
		var rect := Rect2(-half_w, -half_h, w, h)

		var body_col := Color(0.18, 0.44, 0.88, 0.95)
		var body_dark := Color(0.12, 0.28, 0.62)
		var hi_col := Color(0.38, 0.65, 1.0)
		var ink_col := Color(0.08, 0.16, 0.36)

		# 1. Main body capsule
		draw_rect(rect, body_col, true)

		# 2. Highlight ridge on top & left
		draw_line(Vector2(-half_w + 3, -half_h + 3), Vector2(half_w - 3, -half_h + 3), hi_col, 3.0)
		draw_line(Vector2(-half_w + 3, -half_h + 3), Vector2(-half_w + 3, half_h - 3), hi_col, 3.0)

		# 3. Grounding shadow band at bottom
		draw_rect(Rect2(-half_w, half_h - 14 * s.y, w, 14 * s.y), body_dark, true)

		# 4. Crisp outline
		draw_rect(rect, ink_col, false, 2.5)

		# 5. Visor / eyes
		var facing := 1.0 if velocity.x >= -10.0 else -1.0
		var visor_w := 26.0 * s.x
		var visor_h := 16.0 * s.y
		var visor_x := (10.0 if facing > 0 else -10.0 - visor_w) * s.x
		var visor_y := -34.0 * s.y
		var visor_rect := Rect2(visor_x, visor_y, visor_w, visor_h)

		# Visor background & glass glow
		draw_rect(Rect2(visor_x - 2, visor_y - 2, visor_w + 4, visor_h + 4), ink_col, true)
		draw_rect(visor_rect, Color(0.95, 0.98, 1.0), true)
		var pupil_x := visor_x + (visor_w - 9.0 * s.x if facing > 0 else 3.0 * s.x)
		draw_rect(Rect2(pupil_x, visor_y + 3.0 * s.y, 6.0 * s.x, 10.0 * s.y), Color(0.10, 0.22, 0.45), true)

func _on_debug_draw() -> void:
	if Global.debug_toggles.get("show_collisions", false):
		_debug_canvas.draw_rect(Rect2(-40, -55, 80, 110), Color.GREEN, false, 2.0)
		# Parry look-ahead box (the shape scanned for imminent hazards). Turns
		# solid-ish gold while a window is actually open.
		if _use_parry:
			var box := Rect2(PARRY_SCAN_BACK, PARRY_SCAN_FWD - PARRY_SCAN_BACK)
			var col := Color(1.0, 0.85, 0.1, 0.9) if _parry_window_timer > 0.0 else Color(1.0, 0.85, 0.1, 0.5)
			_debug_canvas.draw_rect(box, col, false, 2.0)

func _exit_tree() -> void:
	# Clear any synthetically held actions so they don't bleed into UI.
	Input.action_release("right")
	Input.action_release("left")
	Input.action_release("jump")

## Automatically creates a SpriteFrames resource with all required animation states.
func _auto_setup_sprite_frames() -> void:
	if not anim:
		return

	if not _use_sprite_player:
		anim.visible = false
		queue_redraw()
		# Still register empty animation names so the addon's anim.play("idle") etc.
		# don't spam "There is no animation with name 'idle'" errors.
		_install_stub_sprite_frames()
		return

	anim.visible = true

	var new_frames = SpriteFrames.new()
	# Static or animated based on flags.
	var animations_to_load = {
		"idle":        { "path": "res://assets/animations/player/player_idle", "count": 4 if _use_sprite_anims else 1 },
		"run":         { "path": "res://assets/animations/player/player_run",  "count": 7 if _use_sprite_anims else 1 },
		"walk":        { "path": "res://assets/animations/player/player_run",  "count": 7 if _use_sprite_anims else 1 },
		"jump":        { "path": "res://assets/animations/player/player_jump", "count": 7 if _use_sprite_anims else 1 },
		"falling":     { "path": "res://assets/animations/player/player_jump", "count": 7 if _use_sprite_anims else 1 },
		"slide":       { "path": "res://assets/animations/player/player_run",  "count": 7 if _use_sprite_anims else 1 },
		"latch":       { "path": "res://assets/animations/player/player_idle", "count": 4 if _use_sprite_anims else 1 },
		"crouch_idle": { "path": "res://assets/animations/player/player_idle", "count": 4 if _use_sprite_anims else 1 },
		"crouch_walk": { "path": "res://assets/animations/player/player_run",  "count": 7 if _use_sprite_anims else 1 },
		"roll":        { "path": "res://assets/animations/player/player_run",  "count": 7 if _use_sprite_anims else 1 },
		"hurt_1":      { "path": "res://assets/animations/player/player_hurt_1","count": 3 if _use_sprite_anims else 1 },
		"hurt_2":      { "path": "res://assets/animations/player/player_hurt_2","count": 3 if _use_sprite_anims else 1 },
	}

	for anim_name in animations_to_load:
		if not new_frames.has_animation(anim_name):
			new_frames.add_animation(anim_name)
		new_frames.set_animation_speed(anim_name, 10.0 if _use_sprite_anims else 1.0)
		var is_loop = not (anim_name in ["jump", "falling", "hurt_1", "hurt_2"])
		new_frames.set_animation_loop(anim_name, is_loop and _use_sprite_anims)
		var cfg = animations_to_load[anim_name]
		for f in range(cfg["count"]):
			var path = cfg["path"] + "/" + str(f) + ".png"
			var tex = load(path)
			if tex:
				new_frames.add_frame(anim_name, tex)

	anim.sprite_frames = new_frames

	var new_scale = Vector2(0.5, 0.5)
	anim.scale = new_scale
	animScaleLock = abs(new_scale)
	anim.play("idle")


func _install_stub_sprite_frames() -> void:
	var stub = SpriteFrames.new()
	for anim_name in ["idle", "run", "walk", "jump", "falling", "slide", "latch",
			"crouch_idle", "crouch_walk", "roll", "hurt_1", "hurt_2", "dash"]:
		if not stub.has_animation(anim_name):
			stub.add_animation(anim_name)
	anim.sprite_frames = stub


@onready var dust_particles: CPUParticles2D = $DustParticles
var _was_on_floor: bool = false
var is_dead: bool = false
var game_over_ui: Node = null
var death_y_limit: float = 99999.0

# Momentum-based auto-run
var auto_momentum: float = 0.0
var stun_timer: float = 0.0

# Dynamic zoom
var _base_zoom: float = 1.0
var _zoom_tweened_out: bool = false
var _zoom_tween: Tween = null

# Airborne edge-detect for combo system + stat tracking

var _takeoff_y: float = 0.0
var _peak_y: float = 0.0

# Sensors
var _foot_sensor: Area2D = null
var _body_sensor: Area2D = null
var _screen_sensor: Area2D = null
var _screen_shape: RectangleShape2D = null

func _setup_sensors() -> void:
	_foot_sensor = Area2D.new()
	_foot_sensor.collision_layer = 0
	_foot_sensor.collision_mask  = 4
	var foot_shape = CollisionShape2D.new()
	var foot_rect  = RectangleShape2D.new()
	foot_rect.size = Vector2(50, 20)
	foot_shape.shape = foot_rect
	foot_shape.position = Vector2(0, 60)
	_foot_sensor.add_child(foot_shape)
	add_child(_foot_sensor)
	_foot_sensor.area_entered.connect(_on_foot_sensor_area_entered)
	_foot_sensor.body_entered.connect(_on_foot_sensor_body_entered)

	_screen_sensor = Area2D.new()
	_screen_sensor.collision_layer = 0
	_screen_sensor.collision_mask  = 1
	_screen_sensor.monitoring = true
	_screen_sensor.monitorable = false
	_screen_shape = RectangleShape2D.new()
	_screen_shape.size = Vector2(1280, 720)
	var screen_coll = CollisionShape2D.new()
	screen_coll.shape = _screen_shape
	_screen_sensor.add_child(screen_coll)
	add_child(_screen_sensor)

	_body_sensor = Area2D.new()
	_body_sensor.collision_layer = 8
	_body_sensor.collision_mask  = 0
	var body_shape = CollisionShape2D.new()
	var body_rect  = RectangleShape2D.new()
	body_rect.size = Vector2(60, 90)
	body_shape.shape = body_rect
	body_shape.position = Vector2(0, 0)
	_body_sensor.add_child(body_shape)
	add_child(_body_sensor)

func _on_foot_sensor_area_entered(area: Area2D) -> void:
	if is_dead: return
	if velocity.y > 50:
		var enemy = area.get_parent()
		if enemy and enemy.has_method("stomp_by"):
			var cb := int(enemy.get("combo_bonus") if enemy.get("combo_bonus") != null else 0)
			enemy.stomp_by(self)
			_kick_impact_juice()
			ComboSystem.notify_stomp(global_position, cb)
			Global.stat_add("enemies_stomped", 1)
			# Super-bouncy or bullet → smallsword; regular enemy → bounce
			if cb >= 2:
				AudioManager.play("smallsword", 0.0, 0.10)
			else:
				AudioManager.play("jump_normal", -4.0, 0.08)

func _on_foot_sensor_body_entered(body: Node) -> void:
	if is_dead: return
	if velocity.y > 50 and body.has_method("stomp_by"):
		var cb := int(body.get("combo_bonus") if body.get("combo_bonus") != null else 0)
		body.stomp_by(self)
		_kick_impact_juice()
		ComboSystem.notify_stomp(global_position, cb)
		Global.stat_add("enemies_stomped", 1)
		if cb >= 2:
			AudioManager.play("smallsword", 0.0, 0.10)
		else:
			AudioManager.play("jump_normal", -4.0, 0.08)

# Brief slow-mo + chromatic kick on stomp. No-op if either unlock is off.
func _kick_impact_juice() -> void:
	if _use_impact_freeze:
		Engine.time_scale = 0.06
		# Process-always + ignore-time-scale so the reset still fires at wall time.
		var t = get_tree().create_timer(0.05, true, false, true)
		t.timeout.connect(func(): Engine.time_scale = 1.0)
	if Global.is_unlocked("chromatic_aberration"):
		ScreenFX.kick_chromatic(0.020, 0.35)

func _unhandled_input(event: InputEvent) -> void:
	if is_dead: return
	if event is InputEventKey or event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.is_pressed() and not event.is_echo():
			Input.action_press("jump")
		elif not event.is_pressed():
			Input.action_release("jump")

# ─── MOTION TRAIL ──────────────────────────────────────────────────────────
var _trail: Line2D = null
var _trail_points: Array[Vector2] = []
const TRAIL_LEN := 14

func _setup_motion_trail() -> void:
	if not _use_motion_trail: return
	_trail = Line2D.new()
	_trail.width = 28.0
	_trail.default_color = Color(0.2, 0.4, 0.9, 0.45)
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, 0.0))
	_trail.width_curve = curve
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.z_index = -1
	# Trail is drawn in WORLD space — parent it to the level so it doesn't rotate with us on death.
	call_deferred("_attach_trail_to_world")

func _attach_trail_to_world() -> void:
	if _trail == null: return
	if get_parent() == null: return
	get_parent().add_child(_trail)
	# After this, points pushed into the line are in world coords.

func _tick_motion_trail() -> void:
	if _trail == null: return
	_trail_points.push_front(global_position + Vector2(0, -16))
	if _trail_points.size() > TRAIL_LEN:
		_trail_points.pop_back()
	_trail.clear_points()
	for p in _trail_points:
		_trail.add_point(p)
	if _use_rainbow_trail:
		var hue := fmod(Time.get_ticks_msec() / 1000.0 * 0.6, 1.0)
		_trail.default_color = Color.from_hsv(hue, 0.75, 1.0, 0.5)

# ─── BACKFLIP JUMPS (unlock: backflip_jumps) ────────────────────────────────
var _backflip_tween: Tween = null

## Spin the player sprite a full turn on jump. Cosmetic only — never rotates the
## controller body, so raycasts/collision stay upright.
func _do_backflip() -> void:
	if not (_use_sprite_player and anim): return
	if _backflip_tween and _backflip_tween.is_valid():
		_backflip_tween.kill()
	anim.rotation_degrees = 0.0
	var spin := -360.0 if velocity.x >= 0.0 else 360.0
	_backflip_tween = create_tween()
	_backflip_tween.tween_property(anim, "rotation_degrees", spin, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_backflip_tween.tween_callback(func(): if is_instance_valid(anim): anim.rotation_degrees = 0.0)

# ─── FOOTSTEP DUST ─────────────────────────────────────────────────────────
var _foot_dust: CPUParticles2D = null

func _setup_footstep_dust() -> void:
	if not _use_footstep_dust: return
	_foot_dust = CPUParticles2D.new()
	_foot_dust.texture = Global.get_circle_texture()
	_foot_dust.amount = 16
	_foot_dust.lifetime = 0.42
	_foot_dust.one_shot = false
	_foot_dust.emitting = false
	_foot_dust.explosiveness = 0.0
	_foot_dust.spread = 50.0
	_foot_dust.direction = Vector2(0, -1)
	_foot_dust.gravity = Vector2(0, 240)
	_foot_dust.initial_velocity_min = 60.0
	_foot_dust.initial_velocity_max = 160.0
	_foot_dust.scale_amount_min = 0.1
	_foot_dust.scale_amount_max = 0.25
	_foot_dust.color = Color(0.85, 0.74, 0.55, 0.8)
	_foot_dust.position = Vector2(0, 52)
	add_child(_foot_dust)

func _tick_footstep_dust() -> void:
	if _foot_dust == null: return
	_foot_dust.emitting = is_on_floor() and abs(velocity.x) > 220.0

# ─── HIT FLASH (white) on stun edge ────────────────────────────────────────
var _prev_stun: float = 0.0
func _maybe_hit_flash() -> void:
	if not _use_hit_flash: return
	if stun_timer > 0.0 and _prev_stun <= 0.0:
		var target = anim if (anim and _use_sprite_player) else self
		var tw = create_tween()
		var orig = target.modulate
		tw.tween_property(target, "modulate", Color(1.6, 1.6, 1.6, target.modulate.a), 0.05)
		tw.tween_property(target, "modulate", orig, 0.18)
	_prev_stun = stun_timer

# ─── OUTLINE SHADER ────────────────────────────────────────────────────────
func _apply_outline_material() -> void:
	if not _use_outline: return
	if not anim: return
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/outline.gdshader")
	mat.set_shader_parameter("outline_color", Color(0.10, 0.07, 0.05, 1.0))
	mat.set_shader_parameter("outline_width", 2.2)
	anim.material = mat


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity.y += terminalVelocity * delta
		velocity.x = move_toward(velocity.x, 0.0, 2.0)
		move_and_slide()
		return

	# The addon's multi-jump path (jumps > 1) blocks jump when is_on_wall() is true.
	# Force it here before super runs so the player can still jump off the floor
	# when pressing against a wall.
	if jumps > 1 and is_on_floor() and is_on_wall():
		if Input.is_action_just_pressed("jump"):
			velocity.y = -jumpMagnitude

	var local_limit = get_local_lowest_y() + 192.0 + 200
	if global_position.y > local_limit:
		die(true)
		return

	if stun_timer > 0.0:
		stun_timer -= delta
		auto_momentum = move_toward(auto_momentum, 0.0, auto_acceleration * delta * 4.0)
		Input.action_release("right")
	else:
		auto_momentum = move_toward(auto_momentum, run_speed, auto_acceleration * delta)
		if auto_momentum > 20.0:
			Input.action_press("right")
		else:
			Input.action_release("right")
		if velocity.x > auto_momentum:
			velocity.x = auto_momentum

	var _on_floor_before_jump := is_on_floor()
	_was_on_floor = _on_floor_before_jump
	_maybe_hit_flash()
	super._physics_process(delta)

	# Jump stretch — jumpTap is the addon's one-frame flag: true only on the
	# frame a jump was actually executed. velocity.y < 0 confirms upward launch.
	if jumpTap and velocity.y < 0:
		if dust_particles and _use_particles:
			dust_particles.restart()
			dust_particles.emitting = true
		if _use_juice:
			_squash_and_stretch(Vector2(0.6, 1.4))
		if anim and _use_sprite_anims:
			anim.frame = 0
			anim.play("jump")
		# Floor state before super: true = first jump, false = double jump.
		if _on_floor_before_jump:
			AudioManager.play("jump_normal", 0.0, 0.06)
		else:
			AudioManager.play("jump_spring", 0.0, 0.08)

	# Land squash
	if is_on_floor() and not _was_on_floor:
		if dust_particles and _use_particles:
			dust_particles.restart()
			dust_particles.emitting = true
		if _use_juice:
			_squash_and_stretch(Vector2(1.4, 0.6))
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			if collider and collider.has_method("squash"):
				collider.squash()

	# Track best distance in real time
	var d := int(global_position.x / 128.0)
	if d > Global.last_run_distance:
		Global.stat_add("total_distance_m", d - Global.last_run_distance)
		Global.last_run_distance = d

	# Proactive parry look-ahead (opens the window before we collide).
	if _use_parry:
		_scan_for_parry()

func _squash_and_stretch(target_scale_modifier: Vector2) -> void:
	if not anim: return
	var base_scale = animScaleLock
	if anim.scale.x < 0:
		base_scale.x *= -1
		target_scale_modifier.x *= -1
	var squished_scale = base_scale * abs(target_scale_modifier)
	squished_scale.x *= sign(anim.scale.x) if anim.scale.x != 0 else 1
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(anim, "scale", squished_scale, 0.1)
	tween.tween_property(anim, "scale", base_scale, 0.15)

var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var _shake_timer: float = 0.0

func shake_camera(intensity: float, duration: float) -> void:
	if not _use_shake: return
	shake_intensity = intensity
	shake_duration = duration
	_shake_timer = duration

func _process(delta: float) -> void:
	# Only the primitive (pre-sprite) body and the collider debug boxes are
	# drawn in _draw; once the sprite is bought, redrawing every frame just
	# rebuilds an empty canvas item.
	if Global.debug_toggles.get("show_collisions", false):
		_debug_canvas.queue_redraw()
	if not _use_sprite_player:
		queue_redraw()
	super._process(delta)
	_refresh_group_caches(delta)
	if is_dead:
		ScreenFX.wobble_intensity = 0.0
		return
	# Post-parry slow-motion ramp back to full speed (wall-clock timed so it's
	# unaffected by the very time-scale it's driving).
	if _parry_slow_active:
		var e := float(Time.get_ticks_msec() - _parry_slow_start_ms) / float(PARRY_SLOW_DUR_MS)
		if e >= 1.0:
			Engine.time_scale = 1.0
			_parry_slow_active = false
		else:
			var s := e * e * (3.0 - 2.0 * e)  # smoothstep
			Engine.time_scale = lerp(PARRY_SLOW_MIN, 1.0, s)
	if Global.debug_toggles.get("show_collisions", false):
		queue_redraw()
	# Drive in-air warp shader intensity from vertical speed.
	if Global.is_unlocked("wobble_shader"):
		var vel_y_abs = abs(velocity.y)
		var target_wobble 	= clamp(vel_y_abs / 1200.0, 0.0, 1.0)
		if is_on_floor():
			target_wobble = 0.0
		ScreenFX.wobble_intensity = move_toward(ScreenFX.wobble_intensity, target_wobble, delta * 5.0)
	else:
		ScreenFX.wobble_intensity = 0.0
	# Combo/airtime tracking — edge-detect ground contact.
	var on_floor := is_on_floor()
	if on_floor != _was_on_floor:
		ComboSystem.notify_airborne(not on_floor)
		if not on_floor and velocity.y < -50.0:
			# Leaving the ground upward → count as a jump.
			Global.stat_add("jumps", 1)
			_takeoff_y = global_position.y
			_peak_y = global_position.y
			# Backflip only when this jump happens mid-combo (parry backflips
			# are triggered separately in _execute_parry).
			if _use_backflip and ComboSystem.current_multiplier() > 0:
				_do_backflip()
		elif on_floor and _takeoff_y != 0.0:
			var jump_h := int(_takeoff_y - _peak_y)
			if jump_h > 0:
				Global.stat_max("highest_jump_px", jump_h)
			_takeoff_y = 0.0
		_was_on_floor = on_floor
	if not on_floor and global_position.y < _peak_y:
		_peak_y = global_position.y

	if _shake_timer > 0:
		_shake_timer -= delta
		var cam = _get_camera()
		if cam:
			var t = max(_shake_timer / shake_duration, 0.0)
			var amt = shake_intensity * t
			cam.offset = Vector2(randf_range(-amt, amt), randf_range(-amt, amt))
			if _shake_timer <= 0:
				cam.offset = Vector2.ZERO
	if _use_zoom:
		_update_dynamic_zoom(delta)
	_tick_motion_trail()
	_tick_footstep_dust()
	if _use_near_miss:
		_tick_near_miss(delta)
	if _use_coin_magnet:
		_tick_coin_magnet(delta)
	if _use_parry:
		_tick_parry(delta)
	if _use_double_jump:
		_tick_double_jump_pulse(delta)

## Pulse the player's color while they are airborne with at least one jump
## still banked but not all — a visual "you can still jump again" cue.
## When the outline shader is active, pulses the outline color instead so the
## sprite sprite itself is never tinted (which would be invisible through the shader).
var _dj_pulse_t: float = 0.0
var _dj_pulsing: bool = false
var _dj_orig_modulate: Color = Color.WHITE
var _dj_orig_outline: Color = Color(0.10, 0.07, 0.05, 1.0)
func _tick_double_jump_pulse(delta: float) -> void:
	var can_pulse: bool = (not is_on_floor()) and jumpCount > 0 and jumpCount < jumps
	if can_pulse:
		if not _dj_pulsing:
			_dj_pulsing = true
			_dj_pulse_t = 0.0
			if _use_outline and anim and anim.material is ShaderMaterial:
				_dj_orig_outline = (anim.material as ShaderMaterial).get_shader_parameter("outline_color")
			var target: CanvasItem = anim if (anim and _use_sprite_player and anim.visible) else self
			_dj_orig_modulate = target.modulate
		_dj_pulse_t += delta
		var s: float = 0.5 + 0.5 * sin(_dj_pulse_t * TAU * 2.0)
		# Always pulse the sprite/primitive modulate for a visible color shift.
		var target: CanvasItem = anim if (anim and _use_sprite_player and anim.visible) else self
		var hi_mod := Color(0.55, 1.15, 1.55, _dj_orig_modulate.a)
		target.modulate = _dj_orig_modulate.lerp(hi_mod, s * 0.85)
		# Additionally pulse the outline color when the outline shader is active.
		if _use_outline and anim and anim.material is ShaderMaterial:
			var mat: ShaderMaterial = anim.material as ShaderMaterial
			var hi_out := Color(0.10, 0.95, 1.80, 1.0)
			mat.set_shader_parameter("outline_color", _dj_orig_outline.lerp(hi_out, s))
	elif _dj_pulsing:
		_dj_pulsing = false
		var target: CanvasItem = anim if (anim and _use_sprite_player and anim.visible) else self
		target.modulate = _dj_orig_modulate
		if _use_outline and anim and anim.material is ShaderMaterial:
			(anim.material as ShaderMaterial).set_shader_parameter("outline_color", _dj_orig_outline)

## Detect when the player passes close to a live hazard without touching it and
## roll for a brief slow-motion beat. Uses wall-time timers so the reset fires
## even while Engine.time_scale is low.
func _tick_near_miss(delta: float) -> void:
	if _near_miss_cd > 0.0:
		_near_miss_cd -= delta
	var hazards := _hazards_cache
	var still_close: Dictionary = {}
	for h in hazards:
		if not h: continue
		if not h is Node2D: continue
		if not is_instance_valid(h): continue
		var dist: float = global_position.distance_to((h as Node2D).global_position)
		if dist > NEAR_MISS_RADIUS: continue
		still_close[h] = true
		if _near_miss_active.has(h): continue  # already tracked this pass
		if _near_miss_cd > 0.0: continue
		if randf() > NEAR_MISS_CHANCE: continue
		_trigger_near_miss()
		break
	_near_miss_active = still_close

func _trigger_near_miss() -> void:
	_near_miss_cd = NEAR_MISS_COOLDOWN
	Engine.time_scale = 0.25
	if Global.is_unlocked("chromatic_aberration"):
		ScreenFX.kick_chromatic(0.014, 0.5)
	# Zoom in briefly during the slow-mo beat so the cinematic moment reads clearly.
	if _use_zoom:
		var cam := _get_camera()
		if cam:
			var zoom_in := _base_zoom * 1.22
			var tw := create_tween()
			tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			tw.tween_property(cam, "zoom", Vector2.ONE * zoom_in, 0.12) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 0.5s wall-time slow beat, then restore. Ignore time-scale so it fires reliably.
	var t := get_tree().create_timer(0.5, true, false, true)
	t.timeout.connect(func():
		Engine.time_scale = 1.0
		# Return camera to base zoom after slow-mo ends.
		if _use_zoom:
			var cam := _get_camera()
			if cam:
				var tw2 := create_tween()
				tw2.tween_property(cam, "zoom", Vector2.ONE * _base_zoom, 0.30) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	)

func _update_dynamic_zoom(delta: float) -> void:
	var cam = _get_camera()
	if not cam or _base_zoom <= 0.0: return

	# The lookups below (hazard group scan / physics shape query) are throttled:
	# re-running them a few times per second is plenty since the zoom tweens.
	_zoom_query_timer -= delta
	if _zoom_query_timer <= 0.0:
		_zoom_query_timer = GROUP_REFRESH_INTERVAL
		_zoom_should_out = _compute_should_zoom_out(cam)

	if _zoom_should_out and not _zoom_tweened_out:
		_zoom_tweened_out = true
		_do_zoom_tween(cam, _base_zoom * Global.camera_zoom_out_factor)
	elif not _zoom_should_out and _zoom_tweened_out:
		_zoom_tweened_out = false
		_do_zoom_tween(cam, _base_zoom)

func _compute_should_zoom_out(cam: Camera2D) -> bool:
	match Global.camera_zoom_mode:
		1:
			for h in _hazards_cache:
				if not is_instance_valid(h): continue
				if not h is Node2D: continue
				var dist = h.global_position.x - global_position.x
				if dist > 0 and dist > Global.camera_hazard_distance:
					return true
			return false
		2:
			if _screen_shape:
				var vp_size = get_viewport_rect().size
				var world_w = vp_size.x / cam.zoom.x
				var world_h = vp_size.y / cam.zoom.y
				_screen_shape.size = Vector2(world_w, world_h)

				var query = PhysicsShapeQueryParameters2D.new()
				query.shape = _screen_shape
				query.transform = Transform2D(0.0, global_position)
				query.collision_mask = 1
				query.collide_with_bodies = true
				query.collide_with_areas = false

				var space = get_world_2d().direct_space_state
				var results = space.intersect_shape(query, 64)
				var count := 0
				for r in results:
					var c = r["collider"]
					if not c.is_in_group("solid_tiles"): continue
					# Strips bundle many tile-units in one body — count them properly.
					if c is TileStrip:
						count += int(c.length_tiles)
					else:
						count += 1
				return count < Global.camera_tile_threshold
	return false

func _do_zoom_tween(cam: Camera2D, target_zoom: float) -> void:
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(cam, "zoom", Vector2.ONE * target_zoom, Global.camera_zoom_tween_duration)

func _get_camera() -> Camera2D:
	for child in get_children():
		if child is Camera2D:
			return child
	return null

func die(is_fall: bool = false, cause: String = "", instant_shatter: bool = false) -> void:
	if is_dead: return
	
	# Ghost Mode: intercept death entirely. Gives 3 seconds of translucent invincibility.
	if _use_ghost_mode and not is_fall and not _ghost_active:
		_enter_ghost_mode(cause)
		return

	is_dead = true
	Engine.time_scale = 1.0 # Ensure time is restored if killed during a time-slow (like parry)
	_parry_slow_active = false
	if cause == "" and is_fall:
		cause = "the fall"
	Global.last_death_cause = cause
	# Randomize between hurt and monster_hurt for player death variety.
	var death_sfx := "hurt_player" if randf() < 0.5 else "monster_hurt"
	AudioManager.play(death_sfx, 0.0, 0.08)
	Global.stat_add("deaths", 1)
	if cause != "":
		Global.stat_bucket("deaths_by_cause", cause, 1)
	Global.stat_max("longest_run_m", Global.last_run_distance)

	if _body_sensor:
		_body_sensor.set_deferred("monitoring", false)
		_body_sensor.set_deferred("monitorable", false)
	if _foot_sensor:
		_foot_sensor.set_deferred("monitoring", false)

	Input.action_release("right")
	Input.action_release("jump")

	# In ALL death modes, detach the camera so it stops chasing the dying body.
	# (Tear effects can free the player, taking child nodes with it.)
	var cam = _get_camera()
	if cam:
		var old_global = cam.global_position
		cam.offset = Vector2.ZERO
		cam.position_smoothing_enabled = false
		cam.get_parent().remove_child(cam)
		get_parent().add_child(cam)
		cam.global_position = old_global
		cam.make_current()
		
		# Cursed camera: tilt the view sideways on every hit (after detaching so tween survives).
		if _use_cursed_camera:
			var tilt_deg := 22.0 * (1.0 if randf() < 0.5 else -1.0)
			var tw := create_tween()
			tw.tween_property(cam, "rotation_degrees", tilt_deg, 0.06).set_trans(Tween.TRANS_BACK)
			tw.tween_property(cam, "rotation_degrees", 0.0, 0.34).set_trans(Tween.TRANS_ELASTIC)
	_shake_timer = 0.0

	# Splatter — parented to the level so it survives a tear-effect that hides us.
	BloodSplat.apply(get_parent(), global_position, velocity)

	if is_fall:
		if anim:
			var tween = create_tween()
			tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(anim, "rotation_degrees", 90.0, 0.35)
			tween.parallel().tween_property(anim, "modulate", Color(1.0, 0.2, 0.2, 1.0), 0.2)

		if _use_particles:
			var poof = CPUParticles2D.new()
			poof.texture = Global.get_circle_texture()
			poof.emitting = true
			poof.one_shot = true
			poof.amount = 40
			poof.lifetime = 0.8
			poof.explosiveness = 0.9
			poof.spread = 180.0
			poof.gravity = Vector2(0, 300)
			poof.initial_velocity_min = 150.0
			poof.initial_velocity_max = 400.0
			poof.scale_amount_min = 0.12   # 8–24 px
			poof.scale_amount_max = 0.38
			poof.color = Color(0.4, 0.8, 1.0)
			get_parent().add_child(poof)
			poof.global_position = global_position
			poof.finished.connect(poof.queue_free)
	else:
		# Capture inbound velocity BEFORE zeroing so the tear pieces launch with
		# whatever momentum was in play (knockback from a bomb, forward run
		# speed, etc.). Without this the shatter pieces just plop straight
		# down.
		var tear_impulse: Vector2 = velocity
		collision_layer = 0
		collision_mask = 0
		velocity = Vector2.ZERO
		# Bomb deaths should really throw pieces around. Find the nearest bomb-
		# ish source and add an outward impulse so the shatter reads as blown
		# apart, not merely dropped.
		if cause == "a bomb":
			var blast_src: Vector2 = _find_blast_source()
			var away: Vector2 = (global_position - blast_src)
			if away.length_squared() < 1.0:
				away = Vector2(0, -1)
			away = away.normalized()
			tear_impulse += away * 900.0 + Vector2(0, -400.0)

		# Smasher (and other instant-shatter causes) skip the flash+squash intro
		# and go straight to the tear so the player feels genuinely crushed.
		if not instant_shatter:
			var target_node: Node = anim if (anim and _use_sprite_player) else self
			var death_flash := create_tween()
			death_flash.tween_property(target_node, "modulate",
				Color(2.5, 2.5, 2.5, 1.0), 0.05)
			death_flash.tween_property(target_node, "modulate",
				Color(1.0, 0.18, 0.18, 1.0), 0.10)
			if _use_juice and anim and _use_sprite_player:
				var base_s: Vector2 = animScaleLock if animScaleLock != Vector2.ZERO else Vector2(0.5, 0.5)
				death_flash.parallel().tween_property(anim, "scale",
					base_s * Vector2(1.5, 0.5), 0.07)
				death_flash.tween_property(anim, "scale",
					base_s, 0.12).set_trans(Tween.TRANS_BACK)
			await death_flash.finished

			if anim and _use_sprite_anims:
				var anim_name = "hurt_1" if randf() < 0.5 else "hurt_2"
				anim.play(anim_name)
				await get_tree().process_frame
		if _use_tears:
			# Nudge a nearly-still player so pieces still fly a bit — otherwise
			# a stationary death produces a boring puddle.
			if tear_impulse.length() < 120.0:
				tear_impulse += Vector2(randf_range(-160.0, 160.0), -260.0)
			TearEffect.apply(self, Vector2(80, 110), Color(0.4, 0.8, 1.0), tear_impulse, [], "circular")
		else:
			if anim: anim.visible = false
			visible = _use_sprite_player  # keep something to look at unless primitives

	# Award tokens & remember distance
	var distance_tiles = max(Global.last_run_distance, int(global_position.x / 128.0))
	var awarded = Global.on_player_death(distance_tiles)

	await get_tree().create_timer(1.4).timeout

	if Global.debug_toggles.get("auto_restart", false):
		if not Global.debug_toggles.get("keep_seed", false):
			var level_gen = load("res://level_generator.gd")
			if level_gen:
				level_gen.current_seed = 0
		get_tree().reload_current_scene()
	else:
		if Global.is_tutorial_run():
			var ov = preload("res://tutorial_death_overlay.gd").new()
			get_tree().root.add_child(ov)
		else:
			# Arm the polish guide before asking StoryDB for a scene: if the finger
			# is coming, the "go spend your tokens" reminder stands down instead of
			# saying the same thing one screen earlier.
			Onboarding.arm_phase2()
			# Enemy guide: counts deaths since the last shop visit.
			Global.runs_since_shop += 1
			Global.save_state_deferred()
			Onboarding.arm_phase3()
			# Lore cut first (death-count / distance milestones), then the card.
			var scene: Dictionary = StoryDB.pending("death")
			if not scene.is_empty():
				var cut = preload("res://story_cut.gd").new()
				get_tree().root.add_child(cut)
				cut.play(scene.get("blocks", []), String(scene.get("mode", "black")))
				StoryDB.mark_seen(scene)
				await cut.finished
			if game_over_ui and is_instance_valid(game_over_ui) and game_over_ui.has_method("show_game_over"):
				game_over_ui.show_game_over(awarded, distance_tiles)

## Best-guess origin for a bomb blast. Prefers the closest live bomb node in
## the hazards group; falls back to the player's own position (which nulls the
## outward impulse). The bomb queues itself free during _explode(), so this
## must be called while the bomb still exists.
func _find_blast_source() -> Vector2:
	var best: Vector2 = global_position
	var best_d: float = INF
	for h in get_tree().get_nodes_in_group("hazards"):
		if not is_instance_valid(h): continue
		if not h is Node2D: continue
		var s = h.get_script()
		if s == null: continue
		if not s.resource_path.ends_with("bomb.gd"): continue
		var d: float = global_position.distance_to((h as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = (h as Node2D).global_position
	return best


# ─── COIN MAGNET ───────────────────────────────────────────────────────────
const MAGNET_RADIUS  := 220.0
const MAGNET_RADIUS_SQ := MAGNET_RADIUS * MAGNET_RADIUS
const MAGNET_STRENGTH := 480.0  # px/s pull toward player at edge of radius

func _tick_coin_magnet(_delta: float) -> void:
	var coins := _coins_cache
	for c in coins:
		if not c: continue
		if not c is Node2D: continue
		if not is_instance_valid(c): continue
		var coin = c as Node2D
		var diff: Vector2 = global_position - coin.global_position
		# Squared compare first — this runs over every live coin every frame, and
		# the vast majority are far away, so the sqrt is not worth paying for them.
		var d2: float = diff.length_squared()
		if d2 <= 0.0 or d2 > MAGNET_RADIUS_SQ: continue
		if coin.get("_collected") == true: continue
		if coin.get("flying") == true: continue
		var dist: float = sqrt(d2)
		# Pull strength increases as coin gets closer (inverse-linear).
		var t: float = 1.0 - (dist / MAGNET_RADIUS)
		coin.global_position += (diff / dist) * MAGNET_STRENGTH * t * _delta


# ─── PARRY MECHANIC ────────────────────────────────────────────────────────
## When the player takes an enemy hit, a brief window opens to press Jump and
## perform a parry: the hit is absorbed, the enemy bounces away, and a mid-air
## jump is restored. Gated on \"parry_mechanic\" skill.

const PARRY_WINDOW    := 0.315   # seconds the parry input is accepted
const PARRY_ENEMY_VEL := 800.0  # px/s the parried enemy flies back
const PARRY_BOOST_VEL := 860.0  # px/s the player is launched up on a non-stomp parry
const PARRY_IGNORE_TIME := 1.1  # seconds the parried enemy is phased-out (no collision)
const PARRY_FREEZE    := 0.24   # hitstop hold duration (real seconds) — deliberately long
const PARRY_ZOOM_FACTOR := 1.6  # how hard the camera punches in on a parry
const PARRY_ZOOM_IN   := 0.10   # zoom-in tween duration (real seconds)
const PARRY_ZOOM_OUT  := 0.40   # zoom-out tween back to the previous zoom

# Proactive parry sensor — open the window when a hazard enters a box AHEAD of and
# AROUND the player, before we are already touching it. Auto-run always moves
# right, so the box reaches forward (and up, to catch descending smashers/drills).
const PARRY_SCAN_FWD  := Vector2(90.0, 100.0)    # +x forward, +y down extents
const PARRY_SCAN_BACK := Vector2(-55.0, -175.0)  # -x behind, -y up extents

# After a successful parry, drop time then ease it back to normal over this many
# wall-clock milliseconds so the world (and camera scroll) slows then speeds up.
const PARRY_SLOW_MIN    := 0.35
const PARRY_SLOW_DUR_MS := 900

# Descending-stomp gate. A contact is treated as a stomp (and never a lethal side
# hit) only when the player is moving down AND is above the other body's centre.
const STOMP_SKIP_VEL := 40.0

var _parry_window_timer: float = 0.0  # > 0 while window is open
var _parry_attacker: Node = null      # enemy that opened the parry window
var _parry_consumed: bool = false
var _parry_seen: Dictionary = {}      # hazards already offered a window this pass
var _parry_slow_active: bool = false
var _parry_slow_start_ms: int = 0
var _parry_invuln_until_ms: int = 0    # wall-clock ms until which hazards can't kill

## True when the player is descending onto something whose centre is CLEARLY
## below them — i.e. a genuine overhead stomp handled by the foot sensor, not a
## lethal side/head hit. Read by base_enemy.gd, smasher.gd, drill.gd, spike.gd
## and bomb.gd. The -30 margin keeps side brushes (roughly equal centres) lethal.
func is_stomp_on(other_y: float) -> bool:
	return velocity.y > STOMP_SKIP_VEL and global_position.y < other_y - 30.0

## Brief window of invulnerability opened by a successful parry so the player
## phases cleanly UP through the hazard while it is being disabled. Read by every
## hazard before it kills. Wall-clock timed so it survives the parry slow-mo.
func is_parry_invuln() -> bool:
	return Time.get_ticks_msec() < _parry_invuln_until_ms

## Scan for an imminent hazard inside the look-ahead box and open the parry
## window early so the player can react before the collision lands.
func _scan_for_parry() -> void:
	if _parry_window_timer > 0.0: return
	var lo := global_position + PARRY_SCAN_BACK
	var hi := global_position + PARRY_SCAN_FWD
	var seen_now: Dictionary = {}
	for h in _hazards_cache:
		if not is_instance_valid(h): continue
		if not h is Node2D: continue
		var hp: Vector2 = (h as Node2D).global_position
		if hp.x < lo.x or hp.x > hi.x: continue
		if hp.y < lo.y or hp.y > hi.y: continue
		# Skip already-phased (parried) hazards and things we're cleanly stomping.
		if h is CanvasItem and (h as CanvasItem).modulate.a < 0.6: continue
		if is_stomp_on(hp.y): continue
		seen_now[h] = true
		if _parry_seen.has(h): continue   # already offered while it was in the box
		if _parry_window_timer <= 0.0 and try_open_parry_window(h):
			seen_now[h] = true
	_parry_seen = seen_now

## Called from _on_hitbox_ area_entered path in base_enemy.gd via signal or
## direct call when the player body sensor overlaps a hitbox. We intercept
## the hit here BEFORE die() is called.
func _spawn_floating_text(text: String, color: Color, is_huge: bool = false) -> void:
	if not is_inside_tree(): return
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1, 1.0))
	lbl.add_theme_constant_override("outline_size", 14 if is_huge else 6)
	lbl.add_theme_font_size_override("font_size", 72 if is_huge else 20)
	lbl.z_index = 100
	get_parent().add_child(lbl)
	
	if is_huge:
		# Center it properly and give it a huge pop-in
		lbl.global_position = global_position + Vector2(-110, -96)
		lbl.scale = Vector2(0.1, 0.1)
		lbl.rotation_degrees = -10.0
		var tw = lbl.create_tween()
		tw.tween_property(lbl, "scale", Vector2(1.6, 1.6), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(lbl, "rotation_degrees", 5.0, 0.15)
		tw.tween_property(lbl, "scale", Vector2(1.25, 1.25), 0.1)
		tw.parallel().tween_property(lbl, "rotation_degrees", 0.0, 0.1)
		tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 80.0, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.2)
		tw.tween_callback(lbl.queue_free)
	else:
		lbl.global_position = global_position + Vector2(-20, -40)
		var tw = lbl.create_tween()
		tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 60.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6).set_delay(0.2)
		tw.tween_callback(lbl.queue_free)

func try_open_parry_window(attacker: Node) -> bool:
	if not _use_parry: return false
	if is_dead: return false
	if _parry_window_timer > 0.0: return false  # already parrying something
	_parry_window_timer = PARRY_WINDOW
	_parry_attacker = attacker
	_parry_consumed = false
	# A fresh window overrides any post-parry slow-mo ramp still in progress.
	_parry_slow_active = false

	# Slow time drastically to give the player a clear window to react.
	Engine.time_scale = 0.15
	_spawn_floating_text("!", Color(1.0, 0.9, 0.1))
	AudioManager.play("jump", 0.6, 0.3) # Low-pitch focus sound

	# Flash golden to signal the window.
	var target: CanvasItem = anim if (anim and _use_sprite_player) else self
	var tw := create_tween()
	tw.tween_property(target, "modulate", Color(2.2, 1.8, 0.3, 1.0), 0.05)
	tw.tween_property(target, "modulate", Color.WHITE, 0.12)
	return true  # caller should skip the die() call while window is open

func _tick_parry(delta: float) -> void:
	if _parry_window_timer <= 0.0: return
	
	# delta is scaled by Engine.time_scale! We want the window to be real-time seconds.
	var unscaled_delta = delta / Engine.time_scale if Engine.time_scale > 0.0 else delta
	_parry_window_timer -= unscaled_delta
	
	if Input.is_action_just_pressed("jump") and not _parry_consumed:
		_execute_parry()
	if _parry_window_timer <= 0.0 and not _parry_consumed:
		# Window lapsed with no parry. We do NOT kill here — an un-parried hazard
		# kills on ACTUAL contact (handled by each hazard). If the player never
		# touches it, they simply dodged it. This closes the "jumped through it"
		# hole where a deferred kill missed a fast-moving player.
		Engine.time_scale = 1.0
		_parry_attacker = null
		_spawn_floating_text("MISS", Color(0.8, 0.8, 0.85))

func _execute_parry() -> void:
	if _parry_consumed: return
	_parry_consumed = true
	_parry_window_timer = 0.0
	# Grant a brief phase so the launch-up carries us cleanly THROUGH the hazard
	# while its collision is being disabled (covers the deferred-disable frame).
	_parry_invuln_until_ms = Time.get_ticks_msec() + 350

	_spawn_floating_text("PARRY!", Color(0.1, 1.0, 0.5), true)

	# Special layered audio
	AudioManager.play("gem_gather", 0.0, 1.2)
	AudioManager.play("smallsword", 0.0, 0.7)
	AudioManager.play("smallsword", 2.0, 0.0)

	# Restore a jump so the player keeps momentum after the parry.
	if jumpCount <= 0:
		jumpCount = 1
	elif jumps > 1:
		jumpCount = 1

	# Combo spike + juice.
	ComboSystem.notify_stomp(global_position, 1)
	ScreenFX.kick_chromatic(0.024, 0.4)

	# Was this a stomp-style parry (descending onto the enemy) or a side hit?
	# Only a stomp destroys the creature; a side parry deflects it and launches
	# the player upward instead. Bombs always launch the player up AND detonate.
	var atk := _parry_attacker
	var is_bomb := false
	if is_instance_valid(atk) and atk.get_script():
		is_bomb = atk.get_script().resource_path.ends_with("bomb.gd")

	var was_stomp := false
	if is_instance_valid(atk):
		was_stomp = velocity.y > 50.0 \
			and global_position.y <= atk.global_position.y + 12.0

	if is_bomb and is_instance_valid(atk) and atk.has_method("parry_detonate"):
		# Detonate the bomb (visuals + knockback) but it won't kill us, then
		# launch straight up out of the blast.
		atk.parry_detonate()
		velocity.y = -PARRY_BOOST_VEL
	elif was_stomp and is_instance_valid(atk) and atk.has_method("stomp_by"):
		atk.stomp_by(self)
	else:
		# Non-stomp parry: boost the player up and phase through the hazard so
		# the deflected hit can't immediately re-connect. This is the path taken
		# by smashers, drills and spikes — all send the player UP.
		velocity.y = -PARRY_BOOST_VEL
		_deflect_and_phase(atk, PARRY_IGNORE_TIME)
	_parry_attacker = null

	# Flourish: backflip on every parry.
	if _use_backflip:
		_do_backflip()

	# Cinematic camera: punch in, hold a frozen frame, then ease back out.
	_parry_camera_sequence()

	# Big golden flash on the player.
	var target: CanvasItem = anim if (anim and _use_sprite_player) else self
	var tw := create_tween()
	tw.tween_property(target, "modulate", Color(2.5, 2.2, 0.4, 1.0), 0.06)
	tw.tween_property(target, "scale", anim.scale * 1.3 if anim else scale * 1.3, 0.06)
	tw.tween_property(target, "modulate", Color.WHITE, 0.18)
	tw.parallel().tween_property(target, "scale", anim.scale if anim else scale, 0.18)

## Temporarily disables a parried enemy's hitbox so the deflected hit can't
## re-connect, shoves the creature away, and restores it after `secs` real seconds.
func _deflect_and_phase(enemy, secs: float) -> void:
	if not is_instance_valid(enemy): return
	# Shove the creature back and up.
	var ev = enemy.get("velocity")
	if ev is Vector2:
		var dir := signf(enemy.global_position.x - global_position.x)
		if dir == 0.0: dir = 1.0
		enemy.set("velocity", Vector2(dir * PARRY_ENEMY_VEL, -320.0))
	var hb = enemy.get_node_or_null("Hitbox")
	if hb:
		hb.set_deferred("monitoring", false)
		hb.set_deferred("monitorable", false)
	# Area2D hazards (smasher, drill, spike) have no Hitbox child — disable their
	# own detection so the player only passes through AFTER a successful parry.
	if enemy is Area2D:
		enemy.set_deferred("monitoring", false)
		enemy.set_deferred("monitorable", false)
	if enemy is CanvasItem:
		enemy.modulate.a = 0.45
	var t := get_tree().create_timer(secs, true, false, true)
	t.timeout.connect(func():
		if not is_instance_valid(enemy): return
		var h = enemy.get_node_or_null("Hitbox")
		if h:
			h.set_deferred("monitoring", true)
			h.set_deferred("monitorable", true)
		if enemy is Area2D:
			enemy.set_deferred("monitoring", true)
			enemy.set_deferred("monitorable", true)
		if enemy is CanvasItem:
			enemy.modulate.a = 1.0
	)

## Cinematic parry camera: tween the zoom in, hold a frozen frame (hitstop),
## then tween back out to whatever zoom the camera had before.
func _parry_camera_sequence() -> void:
	var cam := _get_camera()
	if cam == null:
		# No camera — still deliver the hitstop.
		Engine.time_scale = 0.0
		await get_tree().create_timer(PARRY_FREEZE, true, false, true).timeout
		if not is_dead:
			_begin_parry_slowmo()
		return

	var prev_zoom: Vector2 = cam.zoom
	# Phase A — punch in (real time).
	Engine.time_scale = 1.0
	var tin := create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tin.tween_property(cam, "zoom", prev_zoom * PARRY_ZOOM_FACTOR, PARRY_ZOOM_IN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tin.finished

	# Phase B — freeze the frame (longer hitstop).
	Engine.time_scale = 0.0
	await get_tree().create_timer(PARRY_FREEZE, true, false, true).timeout
	if is_dead:
		Engine.time_scale = 1.0
		return

	# Phase C — ease back out to the previous zoom while time slowly ramps up.
	_begin_parry_slowmo()
	if is_instance_valid(cam):
		var tout := create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
		tout.tween_property(cam, "zoom", prev_zoom, PARRY_ZOOM_OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Kick off the post-parry slow-motion: drop time now, then _process eases it
## back to 1.0 over PARRY_SLOW_DUR_MS of wall-clock time.
func _begin_parry_slowmo() -> void:
	if is_dead:
		Engine.time_scale = 1.0
		return
	_parry_slow_active = true
	_parry_slow_start_ms = Time.get_ticks_msec()
	Engine.time_scale = PARRY_SLOW_MIN


# ─── GHOST MODE ────────────────────────────────────────────────────────────
## After dying, ghost mode lets the player run as an invincible translucent
## ghost for 3 extra seconds before the game-over screen appears.
var _ghost_active: bool = false

func _enter_ghost_mode(cause: String) -> void:
	if not _use_ghost_mode: return
	_ghost_active = true
	# Translucent blue tint.
	var target: CanvasItem = anim if (anim and _use_sprite_player) else self
	target.modulate = Color(0.6, 0.8, 1.0, 0.55)
	# Disable all hazard sensors so nothing can kill us during ghost time.
	if _body_sensor: _body_sensor.set_deferred("monitoring", false)
	if _foot_sensor: _foot_sensor.set_deferred("monitoring", false)
	# Floating ghost bob tween loop for 3 s.
	if target == anim:
		var tw := create_tween().set_loops(6)
		tw.tween_property(target, "position:y", target.position.y - 8.0, 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(target, "position:y", target.position.y, 0.25).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(3.0).timeout
	_ghost_active = false
	target.modulate = Color.WHITE
	die(false, cause, false)


func get_local_lowest_y() -> float:
	# The level is static and the result only depends on the player's column,
	# so cache it per tile column instead of rescanning every solid tile every
	# physics frame (called from _physics_process at 60Hz).
	var col := int(global_position.x / 128.0)
	if col != _lowest_y_cache_col:
		_lowest_y_cache_col = col
		_lowest_y_cache = _compute_local_lowest_y()
	return _lowest_y_cache

func _compute_local_lowest_y() -> float:
	var player_x = global_position.x
	var lowest_y = -999999.0
	var found = false
	for tile in get_tree().get_nodes_in_group("solid_tiles"):
		if not tile is Node2D: continue
		var half_w = 64.0
		var centre_x = tile.global_position.x
		if tile is TileStrip:
			var ts: TileStrip = tile
			half_w = ts.length_tiles * ts.tile_size.x * 0.5
			centre_x = tile.global_position.x + half_w - ts.tile_size.x * 0.5
		if abs(centre_x - player_x) < half_w + 384.0:
			if tile.global_position.y > lowest_y:
				lowest_y = tile.global_position.y
				found = true
	if found:
		return lowest_y
	return 2000.0
