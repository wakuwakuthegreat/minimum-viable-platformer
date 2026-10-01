# Suggested asset size: 64x64 px
extends BaseEnemy

@export var walk_speed: float = 100.0
@export var trigger_distance: float = 400.0
@export var explosion_delay: float = 1.0
@export var explosion_radius: float = 250.0

var state = "walking" # walking, loading, exploding
var timer: float = 0.0
var color_mod = Color(0.1, 0.1, 0.1)

## Built once and shared by every explosion poof — fixed colors, no reason to
## allocate + rebuild this every time a bomb goes off.
static var _poof_ramp: Gradient = null

static func _get_poof_ramp() -> Gradient:
	if _poof_ramp == null:
		_poof_ramp = Gradient.new()
		_poof_ramp.set_color(0, Color(1.0, 0.75, 0.2, 1.0))
		_poof_ramp.set_color(1, Color(0.6, 0.15, 0.0, 0.0))
	return _poof_ramp

func _ready() -> void:
	super._ready()
	tear_size      = Vector2(64, 64)
	tear_color     = Color(0.12, 0.12, 0.12)
	tears_on_death = false  # bomb uses its own explosion effect
	var coll = $CollisionShape2D
	if coll and coll.shape is RectangleShape2D:
		coll.shape.size = Vector2(64, 64)
	var hitbox_coll = $Hitbox/CollisionShape2D
	if hitbox_coll and hitbox_coll.shape is RectangleShape2D:
		hitbox_coll.shape.size = Vector2(74, 74)
	# Expand the Hitbox to also detect CharacterBody2D bodies (enemies on layer 2,
	# player body on layer 1). area_entered already covers the player body sensor (layer 8).
	var hitbox = $Hitbox
	if hitbox:
		hitbox.collision_mask = hitbox.collision_mask | 1 | 2
		hitbox.body_entered.connect(_on_body_entered_bomb)

func _custom_process(delta: float) -> void:
	if not player: return
	
	match state:
		"walking":
			if false and 	is_on_floor():
				var dir = sign(player.global_position.x - global_position.x)
				if dir == 0: dir = 1
				velocity.x = dir * walk_speed
				
			if abs(player.global_position.x - global_position.x) < trigger_distance:
				state = "loading"
				timer = explosion_delay
				velocity.x = 0
		"loading":
			velocity.x = 0
			timer -= delta
			# Pulse red
			var pulse = (sin(timer * 30) + 1.0) / 2.0
			color_mod = Color(pulse, 0.1, 0.1)
			queue_redraw()
			
			if timer <= 0:
				_explode()

## When anything touches our hitbox from the side/below, explode immediately.
## Top contact (stomp) is handled by the foot sensor and triggers a normal stomp-die.
func _on_hitbox_area_entered(area: Area2D) -> void:
	if _is_dying: return
	_bomb_contact(area.get_parent())

func _on_body_entered_bomb(body: Node2D) -> void:
	if _is_dying: return
	# Ignore floor tiles and self.
	if body == self: return
	if body.is_in_group("solid_tiles"): return
	_bomb_contact(body)

## Shared contact resolution. The player gets the stomp/parry treatment; anything
## else that walks into a live bomb sets it off.
func _bomb_contact(body: Node) -> void:
	if _is_dying or state == "exploding": return
	if body == null or not body.has_method("die"): return
	if body.get("is_dead"): return
	if body.has_method("try_open_parry_window"):
		# Genuine stomp → foot sensor handles it.
		if body.has_method("is_stomp_on") and body.is_stomp_on(global_position.y):
			return
		elif not body.has_method("is_stomp_on") and body.global_position.y < global_position.y - 30:
			return
		# Just parried (this bomb is detonated separately) → don't chain-explode.
		if body.has_method("is_parry_invuln") and body.is_parry_invuln():
			return
	_explode()

## Parry response: detonate with full visuals + knockback but never kill the
## player who parried us. Called from player._execute_parry().
func parry_detonate() -> void:
	if _is_dying or state == "exploding": return
	state = "exploding"
	_is_dying = true
	if player and player.has_method("shake_camera"):
		player.shake_camera(40.0, 0.5)
	_apply_explosion_knockback(explosion_radius * 1.5)
	queue_free()

const KNOCKBACK_IMPULSE := 3500.0
const KNOCKBACK_LIFT := 1000.0

func _explode() -> void:
	state = "exploding"

	if player and player.has_method("shake_camera"):
		player.shake_camera(40.0, 0.5)

	# Knock back anything within ~1.5× the kill radius so nearby survivors
	# feel the shockwave even if they're outside the lethal zone.
	_apply_explosion_knockback(explosion_radius * 1.5)

	var dist = global_position.distance_to(player.global_position)
	if dist <= explosion_radius:
		if player.has_method("die"):
			player.die(false, "a bomb", true)

## Push every knockable body away from the blast with an impulse that falls off
## with distance. Applies to CharacterBody2D (enemies, player) via velocity and
## RigidBody2D via apply_impulse.
func _apply_explosion_knockback(radius: float) -> void:
	var candidates: Array = []
	candidates.append_array(get_tree().get_nodes_in_group("hazards"))
	candidates.append_array(get_tree().get_nodes_in_group("player"))
	for n in candidates:
		if n == self: continue
		if not is_instance_valid(n): continue
		if not n is Node2D: continue
		var np: Vector2 = (n as Node2D).global_position
		var d: float = global_position.distance_to(np)
		if d > radius: continue
		var falloff: float = 1.0 - clamp(d / radius, 0.0, 1.0)
		var dir: Vector2 = (np - global_position)
		if dir.length_squared() < 1.0:
			dir = Vector2.UP
		dir = dir.normalized()
		var impulse: Vector2 = dir * KNOCKBACK_IMPULSE * falloff + Vector2(0, -KNOCKBACK_LIFT * falloff)
		if n is CharacterBody2D:
			(n as CharacterBody2D).velocity += impulse
		elif n is RigidBody2D:
			(n as RigidBody2D).apply_impulse(impulse)
	
	# Visual only — the blast and knockback above happen regardless. Before
	# Particles is bought a bomb just vanishes, like every other effect.
	if Global.is_unlocked("sprite_explosion"):
		_spawn_sprite_explosion()
	elif Global.is_unlocked("particles"):
		var poof = CPUParticles2D.new()
		poof.texture = Global.get_circle_texture()
		poof.emitting = true
		poof.one_shot = true
		poof.amount = 40
		poof.lifetime = 0.5
		poof.explosiveness = 1.0
		poof.spread = 180.0
		poof.initial_velocity_min = 200.0
		poof.initial_velocity_max = 520.0
		poof.scale_amount_min = 0.19   # 12–36 px
		poof.scale_amount_max = 0.56
		poof.color = Color(1.0, 0.4, 0.0)
		poof.color_ramp = _get_poof_ramp()
		get_parent().add_child(poof)
		poof.global_position = global_position
		poof.finished.connect(poof.queue_free)

	queue_free()

## Built once and shared by every bomb — loading 12 textures per explosion was
## a hitch on phones.
static var _boom_frames: SpriteFrames = null

static func _explosion_frames() -> SpriteFrames:
	if _boom_frames != null: return _boom_frames
	var folder := "res://assets/animations/explosion/"
	var frames := SpriteFrames.new()
	frames.add_animation("boom")
	frames.set_animation_loop("boom", false)
	frames.set_animation_speed("boom", 24.0)
	# ResourceLoader.list_directory, not DirAccess: in an exported build the
	# .png files are remapped and DirAccess only lists their .import stubs, so
	# the explosion was silently empty on phones.
	var files: Array = []
	for f in ResourceLoader.list_directory(folder):
		if f.ends_with(".png"): files.append(f)
	files.sort_custom(func(a, b):
		return int(a.get_basename()) < int(b.get_basename())
	)
	for f in files:
		var tex: Texture2D = load(folder + f)
		if tex: frames.add_frame("boom", tex)
	_boom_frames = frames
	return frames

func _spawn_sprite_explosion() -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _explosion_frames()
	sprite.global_position = global_position
	# Pixel art: nearest filtering at a whole-number scale keeps it crisp.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(2.0, 2.0)
	get_parent().add_child(sprite)
	sprite.play("boom")
	sprite.animation_finished.connect(sprite.queue_free)

func _draw() -> void:
	# Bomb body
	draw_circle(Vector2(0, 0), 32, color_mod)
	# Fuse
	draw_line(Vector2(0, -32), Vector2(10, -50), Color.DARK_GRAY, 4.0)
	if state == "loading":
		draw_circle(Vector2(10, -50), 8, Color.YELLOW)
		draw_circle(Vector2(10, -50), 4, Color.ORANGE)
