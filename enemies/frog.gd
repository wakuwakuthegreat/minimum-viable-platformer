# Suggested asset size: 64x64 px
extends BaseEnemy

@export var hop_distance: float = 600.0
@export var hop_velocity: Vector2 = Vector2(400, -800)
@export var hop_cooldown: float = 1.5

var timer: float = 0.0

var anim: AnimatedSprite2D = null

## Built once and shared by every frog — see bomb.gd's _boom_frames for why
## per-instance load() of animation frames was a hitch on phones.
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
	tear_size  = Vector2(64, 64)
	tear_color = Color(0.2, 0.8, 0.2)
	# Ensure shapes match the 64x64 size
	var coll = $CollisionShape2D
	if coll and coll.shape is RectangleShape2D:
		coll.shape.size = Vector2(64, 64)
	var hitbox_coll = $Hitbox/CollisionShape2D
	if hitbox_coll and hitbox_coll.shape is RectangleShape2D:
		hitbox_coll.shape.size = Vector2(74, 74)

	if Global.gfx("enemy_sprites"):
		anim = AnimatedSprite2D.new()
		anim.sprite_frames = _get_frog_frames()
		# 64 / 160 = 0.4 scale to match collision height while keeping aspect ratio
		anim.scale = Vector2(0.4, 0.4)
		add_child(anim)
		anim.play("idle")

func _custom_process(delta: float) -> void:
	if not player: return
	
	timer -= delta
	
	if is_on_floor():
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

func _draw() -> void:
	if not Global.gfx("enemy_sprites") or not anim:
		draw_circle(Vector2(0, 0), 32, Color(0.2, 0.8, 0.2)) # Green body
		# Eyes
		draw_circle(Vector2(-15, -15), 8, Color.WHITE)
		draw_circle(Vector2(15, -15), 8, Color.WHITE)
		draw_circle(Vector2(-15, -15), 4, Color.BLACK)
		draw_circle(Vector2(15, -15), 4, Color.BLACK)

	if Global.debug_toggles.get("show_collisions", false):
		draw_rect(Rect2(-32, -32, 64, 64), Color.GREEN, false, 2.0)

