# Suggested asset size: 64x64 px
extends BaseEnemy

@export var fly_speed: float = 200.0
@export var trigger_distance: float = 1000.0

var anim: AnimatedSprite2D = null

## Built once and shared by every bat — see bomb.gd's _boom_frames for why
## per-instance load() of animation frames was a hitch on phones.
static var _fly_frames: SpriteFrames = null

static func _get_fly_frames() -> SpriteFrames:
	if _fly_frames != null: return _fly_frames
	var frames := SpriteFrames.new()
	frames.add_animation("fly")
	for f in range(4):
		var tex = load("res://assets/animations/bat/" + str(f) + ".png")
		if tex:
			frames.add_frame("fly", tex)
	frames.set_animation_speed("fly", 12.0)
	frames.set_animation_loop("fly", true)
	_fly_frames = frames
	return frames

func _ready() -> void:
	gravity_scale = 0.0 # Ignore gravity
	super._ready()
	tear_size  = Vector2(64, 48)
	tear_color = Color(0.2, 0.2, 0.22)
	var coll = $CollisionShape2D
	if coll and coll.shape is RectangleShape2D:
		coll.shape.size = Vector2(64, 64)
	var hitbox_coll = $Hitbox/CollisionShape2D
	if hitbox_coll and hitbox_coll.shape is RectangleShape2D:
		hitbox_coll.shape.size = Vector2(74, 74)

	if Global.gfx("enemy_sprites"):
		anim = AnimatedSprite2D.new()
		anim.sprite_frames = _get_fly_frames()
		anim.scale = Vector2(0.4, 0.4)
		add_child(anim)
		anim.play("fly")

var triggered: bool = false

func _custom_process(delta: float) -> void:
	if not player: return
	
	if not triggered:
		var dist = global_position.distance_to(player.global_position)
		if dist < trigger_distance:
			triggered = true
			# Calculate a steep downward dive direction
			var dir = global_position.direction_to(player.global_position)
			dir.y = max(dir.y, 0.8) # Force a steep downward trajectory
			velocity = dir.normalized() * fly_speed
		else:
			velocity = velocity.move_toward(Vector2.ZERO, fly_speed * delta)
	
	if anim and velocity.x != 0:
		# Flip based on moving direction
		anim.flip_h = velocity.x < 0

func _draw() -> void:
	if not Global.gfx("enemy_sprites") or not anim:
		# Draw bat wings and body
		var points = PackedVector2Array()
		points.append(Vector2(0, -10))
		points.append(Vector2(-32, -32))
		points.append(Vector2(-10, 0))
		points.append(Vector2(-32, 32))
		points.append(Vector2(0, 10))
		points.append(Vector2(32, 32))
		points.append(Vector2(10, 0))
		points.append(Vector2(32, -32))
		draw_polygon(points, PackedColorArray([Color(0.2, 0.2, 0.2)]))
		# Red eyes
		draw_circle(Vector2(-5, -5), 3, Color.RED)
		draw_circle(Vector2(5, -5), 3, Color.RED)

	if Global.debug_toggles.get("show_collisions", false):
		draw_rect(Rect2(-32, -32, 64, 64), Color.GREEN, false, 2.0)

