# Suggested asset size: 128x128 px
extends BaseEnemy

@export var hop_distance: float = 600.0
@export var hop_velocity: Vector2 = Vector2(500, -1000)
@export var hop_cooldown: float = 2.0

var timer: float = 0.0
var _was_on_floor: bool = false

var anim: AnimatedSprite2D = null

## Built once and shared by every big frog — see bomb.gd's _boom_frames for why
## per-instance load() of animation frames was a hitch on phones. Same source
## frames as frog.gd; kept as its own cache since big_frog scales the sprite
## node itself differently, not the SpriteFrames resource.
static var _frog_frames: SpriteFrames = null

static func _get_frog_frames() -> SpriteFrames:
	if _frog_frames != null: return _frog_frames
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	var idle_tex = load("res://assets/animations/frog_idle/0.png")
	if idle_tex:
		frames.add_frame("idle", idle_tex)
	frames.add_animation("jump")
	for f in range(4):
		var jump_tex = load("res://assets/animations/frog_jump/" + str(f) + ".png")
		if jump_tex:
			frames.add_frame("jump", jump_tex)
	frames.set_animation_speed("idle", 10.0)
	frames.set_animation_speed("jump", 10.0)
	frames.set_animation_loop("idle", true)
	frames.set_animation_loop("jump", false)
	_frog_frames = frames
	return frames

func _ready() -> void:
	super._ready()
	tear_size  = Vector2(128, 128)
	tear_color = Color(0.1, 0.5, 0.1)
	var coll = $CollisionShape2D
	if coll and coll.shape is RectangleShape2D:
		coll.shape.size = Vector2(128, 128)
	var hitbox_coll = $Hitbox/CollisionShape2D
	if hitbox_coll and hitbox_coll.shape is RectangleShape2D:
		hitbox_coll.shape.size = Vector2(138, 138)

	if Global.gfx("enemy_sprites"):
		anim = AnimatedSprite2D.new()
		anim.sprite_frames = _get_frog_frames()
		# 128 / 160 = 0.8 scale to match collision height while keeping aspect ratio
		anim.scale = Vector2(0.8, 0.8)
		add_child(anim)
		anim.play("idle")

func _custom_process(delta: float) -> void:
	if not player: return
	
	timer -= delta
	var currently_on_floor = is_on_floor()
	
	if currently_on_floor and not _was_on_floor:
		_break_tiles_below()
		
	_was_on_floor = currently_on_floor
	
	if currently_on_floor:
		velocity.x = move_toward(velocity.x, 0, 800 * delta)
		if anim and anim.animation != "idle":
			anim.play("idle")
		
		if timer <= 0.0 and abs(player.global_position.x - global_position.x) < hop_distance:
			var dir = sign(player.global_position.x - global_position.x)
			if dir == 0: dir = 1
			velocity = Vector2(hop_velocity.x * dir, hop_velocity.y)
			timer = hop_cooldown
			if anim:
				anim.frame = 0
				anim.play("jump")

	if anim and velocity.x != 0:
		anim.flip_h = velocity.x < 0

func _break_tiles_below() -> void:
	if player and player.has_method("shake_camera"):
		player.shake_camera(30.0, 0.4)
		
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider is TileObject and collision.get_normal().y < -0.5:
			collider.queue_free()

func _draw() -> void:
	if not Global.gfx("enemy_sprites") or not anim:
		draw_circle(Vector2(0, 0), 64, Color(0.1, 0.5, 0.1)) # Dark green body
		# Eyes
		draw_circle(Vector2(-30, -30), 16, Color.WHITE)
		draw_circle(Vector2(30, -30), 16, Color.WHITE)
		draw_circle(Vector2(-30, -30), 8, Color.BLACK)
		draw_circle(Vector2(30, -30), 8, Color.BLACK)

	if Global.debug_toggles.get("show_collisions", false):
		draw_rect(Rect2(-64, -64, 128, 128), Color.GREEN, false, 2.0)
