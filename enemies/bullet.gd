# Suggested asset size: 64x48 px
extends BaseEnemy

@export var fly_speed: float = 400.0
var direction: int = -1

var anim: AnimatedSprite2D = null

## Built once and shared by every bullet — see bomb.gd's _boom_frames for why
## per-instance load() of animation frames was a hitch on phones.
static var _fly_frames: SpriteFrames = null

static func _get_fly_frames() -> SpriteFrames:
	if _fly_frames != null: return _fly_frames
	var frames := SpriteFrames.new()
	frames.add_animation("fly")
	for f in range(4):
		var tex = load("res://assets/animations/bullet_bob/" + str(f) + ".png")
		if tex:
			frames.add_frame("fly", tex)
	frames.set_animation_speed("fly", 10.0)
	frames.set_animation_loop("fly", true)
	_fly_frames = frames
	return frames

func _ready() -> void:
	gravity_scale  = 0.0  # Bullets fly straight
	can_be_stomped = true
	tears_on_death = true
	tear_type      = "logs"
	tear_size      = Vector2(64, 48)
	tear_color     = Color(0.12, 0.12, 0.12)
	super._ready()
	collision_mask = 1  # Only collide with walls (not other enemies physically)

	var coll = $CollisionShape2D
	if coll and coll.shape is RectangleShape2D:
		coll.shape.size = Vector2(64, 48)
	var hitbox_coll = $Hitbox/CollisionShape2D
	if hitbox_coll and hitbox_coll.shape is RectangleShape2D:
		hitbox_coll.shape.size = Vector2(74, 58)

	if Global.gfx("enemy_sprites"):
		anim = AnimatedSprite2D.new()
		anim.sprite_frames = _get_fly_frames()
		anim.scale = Vector2(0.4, 0.4)
		add_child(anim)
		anim.play("fly")
		anim.flip_h = direction < 0

	# Area2D that detects ALL enemy bodies (layer 2) — kills them on contact
	var dmg_area = Area2D.new()
	dmg_area.collision_layer = 0
	dmg_area.collision_mask  = 2  # enemy CharacterBody2D layer
	var dmg_shape = CollisionShape2D.new()
	var dmg_rect  = RectangleShape2D.new()
	dmg_rect.size = Vector2(64, 48)
	dmg_shape.shape = dmg_rect
	dmg_area.add_child(dmg_shape)
	add_child(dmg_area)
	dmg_area.body_entered.connect(_on_hit_enemy)

func _on_hit_enemy(body: Node) -> void:
	if _is_dying: return
	if body == self: return
	if body is BaseEnemy:
		body.die_torn(Vector2(direction * fly_speed, 0.0))
		die()  # bullet also dies (poof) when it kills

func _custom_process(_delta: float) -> void:
	velocity.x = direction * fly_speed
	if is_on_wall():
		die()

	if anim:
		anim.flip_h = direction < 0

func stomp_by(stomper: Node2D) -> void:
	if _is_dying: return
	AudioManager.play("smallsword", 0.0, 0.10)
	die()
	var body_vel = stomper.get("velocity")
	if body_vel is Vector2:
		stomper.set("velocity", Vector2(body_vel.x, -700))

func _draw() -> void:
	if not Global.gfx("enemy_sprites") or not anim:
		draw_rect(Rect2(-32, -24, 64, 48), Color(0.1, 0.1, 0.1))
		var points = PackedVector2Array()
		if direction < 0:
			points.append(Vector2(-32, -24))
			points.append(Vector2(-48,   0))
			points.append(Vector2(-32,  24))
		else:
			points.append(Vector2( 32, -24))
			points.append(Vector2( 48,   0))
			points.append(Vector2( 32,  24))
		draw_polygon(points, PackedColorArray([Color(0.2, 0.2, 0.2)]))
		var eye_x = direction * 15
		draw_circle(Vector2(eye_x,                 -5), 5, Color.WHITE)
		draw_circle(Vector2(eye_x + direction * 2, -5), 2, Color.RED)

	if Global.debug_toggles.get("show_collisions", false):
		draw_rect(Rect2(-32, -24, 64, 48), Color.GREEN, false, 2.0)

