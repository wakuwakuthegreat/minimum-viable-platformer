# Suggested asset size: 64x96 px
extends BaseEnemy

@export var walk_speed: float = 150.0
var direction: int = -1

var anim: AnimatedSprite2D = null

## Built once and shared by every kobold — see bomb.gd's _boom_frames for why
## per-instance load() of animation frames was a hitch on phones.
static var _walk_frames: SpriteFrames = null

static func _get_walk_frames() -> SpriteFrames:
	if _walk_frames != null: return _walk_frames
	var frames := SpriteFrames.new()
	frames.add_animation("walk")
	for f in range(8):
		var tex = load("res://assets/animations/kobold/" + str(f) + ".png")
		if tex:
			frames.add_frame("walk", tex)
	frames.set_animation_speed("walk", 12.0)
	frames.set_animation_loop("walk", true)
	_walk_frames = frames
	return frames

func _ready() -> void:
	super._ready()
	tear_size  = Vector2(64, 96)
	tear_color = Color(0.8, 0.5, 0.2)
	var coll = $CollisionShape2D
	if coll and coll.shape is RectangleShape2D:
		coll.shape.size = Vector2(64, 96)
	var hitbox_coll = $Hitbox/CollisionShape2D
	if hitbox_coll and hitbox_coll.shape is RectangleShape2D:
		hitbox_coll.shape.size = Vector2(74, 106)

	if Global.gfx("enemy_sprites"):
		anim = AnimatedSprite2D.new()
		anim.sprite_frames = _get_walk_frames()
		anim.scale = Vector2(0.436, 0.436)
		add_child(anim)
		anim.play("walk")
		anim.flip_h = direction < 0

func _custom_process(delta: float) -> void:
	if is_on_floor():
		var ray_l = $RayCastLeft
		var ray_r = $RayCastRight

		if is_on_wall():
			direction *= -1
		elif direction == -1 and ray_l and not ray_l.is_colliding():
			direction = 1
		elif direction == 1 and ray_r and not ray_r.is_colliding():
			direction = -1

		velocity.x = direction * walk_speed

	if anim:
		anim.flip_h = direction < 0

func _draw() -> void:
	if not Global.gfx("enemy_sprites") or not anim:
		draw_rect(Rect2(-32, -48, 64, 96), Color(0.8, 0.5, 0.2)) # Kobold color
		var eye_x = direction * 15
		draw_circle(Vector2(eye_x - 8, -30), 4, Color.RED)
		draw_circle(Vector2(eye_x + 8, -30), 4, Color.RED)
		draw_line(Vector2(eye_x - 12, -40), Vector2(eye_x - 4, -35), Color.BLACK, 2)
		draw_line(Vector2(eye_x + 12, -40), Vector2(eye_x + 4, -35), Color.BLACK, 2)

	if Global.debug_toggles.get("show_collisions", false):
		draw_rect(Rect2(-32, -48, 64, 96), Color.GREEN, false, 2.0)
