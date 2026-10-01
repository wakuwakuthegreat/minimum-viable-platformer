# Suggested asset size: 128x128 px
extends BaseEnemy

@export var rush_speed: float = 200.0
@export var trigger_distance: float = 600.0
@export var bounce_velocity: float = -1400.0

func _ready() -> void:
	can_be_stomped = true
	super._ready()
	tear_size  = Vector2(128, 96)
	tear_color = Color(0.8, 0.2, 0.2)  # Red spring top
	var coll = $CollisionShape2D
	if coll and coll.shape is RectangleShape2D:
		coll.shape.size = Vector2(128, 128)
	var hitbox_coll = $Hitbox/CollisionShape2D
	if hitbox_coll and hitbox_coll.shape is RectangleShape2D:
		hitbox_coll.shape.size = Vector2(138, 138)

	# Separate wide Area2D for bouncing enemy bodies (layer 2)
	var bounce_area = Area2D.new()
	bounce_area.collision_layer = 0
	bounce_area.collision_mask  = 2  # enemy CharacterBody2D layer
	var ba_shape = CollisionShape2D.new()
	var ba_rect  = RectangleShape2D.new()
	ba_rect.size = Vector2(148, 148)  # slightly larger than body
	ba_shape.shape = ba_rect
	bounce_area.add_child(ba_shape)
	add_child(bounce_area)
	bounce_area.body_entered.connect(_on_bounce_enemy)

func stomp_by(stomper: Node2D) -> void:
	# Do NOT die. Just launch the player incredibly high.
	var body_vel = stomper.get("velocity")
	if body_vel is Vector2:
		stomper.set("velocity", Vector2(body_vel.x, bounce_velocity))
		if stomper.has_method("shake_camera"):
			stomper.shake_camera(10.0, 0.2)

func _on_hitbox_area_entered(area: Area2D) -> void:
	if _is_dying: return
	var body = area.get_parent()
	if not body: return
	if not body.has_method("die"): return
	if body.get("is_dead"): return
	
	# Player centre more than 30 px above our centre → overhead / head contact → do nothing here (stomp handles it)
	if body.global_position.y < global_position.y - 30:
		return
		
	# Harmless on side touch — zero the player's auto-momentum then knock them back
	var knockback_dir = sign(body.global_position.x - global_position.x)
	if knockback_dir == 0: knockback_dir = 1
	# Suppress auto-run briefly so the bounce force actually carries them
	body.set("stun_timer", 0.55)
	body.set("auto_momentum", 0.0)
	body.set("velocity", Vector2(knockback_dir * 1100, -380))

func _custom_process(delta: float) -> void:
	if not player: return
	if is_on_floor():
		if abs(player.global_position.x - global_position.x) < trigger_distance:
			var dir = sign(player.global_position.x - global_position.x)
			if dir == 0: dir = 1
			velocity.x = move_toward(velocity.x, dir * rush_speed, 800 * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, 500 * delta)

## Bounce any enemy body that enters our bounce area — large horizontal throw
func _on_bounce_enemy(body: Node) -> void:
	if _is_dying: return
	if not body is BaseEnemy: return
	if body == self: return
	if body.get("_is_dying"): return
	var knockback_dir = sign(body.global_position.x - global_position.x)
	if knockback_dir == 0: knockback_dir = 1
	body.velocity = Vector2(knockback_dir * 1400, -400)

func _draw() -> void:
	# Draw base
	draw_rect(Rect2(-64, -16, 128, 80), Color(0.4, 0.4, 0.4))
	# Draw spring/mushroom
	draw_rect(Rect2(-32, -64, 64, 48), Color(0.8, 0.2, 0.2))
	# Draw eyes
	draw_circle(Vector2(-20, -5), 8, Color.YELLOW)
	draw_circle(Vector2(20, -5), 8, Color.YELLOW)


