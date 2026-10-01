# Suggested asset size: 64x64 px
extends BaseEnemy

@export var hop_distance: float = 500.0
@export var hop_velocity: Vector2 = Vector2(250, -500)
@export var hop_cooldown: float = 2.2
@export var launch_velocity: float = -2400.0

var timer: float = 0.0

func _ready() -> void:
	super._ready()
	tear_size  = Vector2(64, 64)
	tear_color = Color(0.9, 0.2, 0.9)  # Bright Purple
	combo_bonus = 2+1  # bouncy stomp — big combo kick
	var coll = $CollisionShape2D
	if coll and coll.shape is RectangleShape2D:
		coll.shape.size = Vector2(64, 64)
	var hitbox_coll = $Hitbox/CollisionShape2D
	if hitbox_coll and hitbox_coll.shape is RectangleShape2D:
		hitbox_coll.shape.size = Vector2(74, 74)

func stomp_by(stomper: Node2D) -> void:
	if _is_dying: return
	AudioManager.play("jump_spring", 0.0, 0.08)
	die()
	var body_vel = stomper.get("velocity")
	if body_vel is Vector2:
		stomper.set("velocity", Vector2(body_vel.x, launch_velocity))
		if stomper.has_method("shake_camera"):
			stomper.shake_camera(15.0, 0.3)

func _custom_process(delta: float) -> void:
	if not player: return
	
	timer -= delta
	
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0, 800 * delta)
		
		if timer <= 0.0 and abs(player.global_position.x - global_position.x) < hop_distance:
			var dir = sign(player.global_position.x - global_position.x)
			if dir == 0: dir = 1
			velocity = Vector2(hop_velocity.x * dir, hop_velocity.y)
			timer = hop_cooldown
			if AudioManager.is_on_screen(global_position):
				AudioManager.play("jump_spring", -6.0, 0.10)

func _draw() -> void:
	# Draw purple bouncy/frog visual
	draw_circle(Vector2(0, 0), 32, Color(0.9, 0.2, 0.9))
	# Draw bouncy pattern/spiral
	draw_circle(Vector2(0, 0), 20, Color(1.0, 0.6, 1.0))
	draw_circle(Vector2(0, 0), 10, Color(0.9, 0.2, 0.9))
	
	# Small eyes
	draw_circle(Vector2(-12, -12), 6, Color.WHITE)
	draw_circle(Vector2(12, -12), 6, Color.WHITE)
	draw_circle(Vector2(-12, -12), 3, Color.BLACK)
	draw_circle(Vector2(12, -12), 3, Color.BLACK)
