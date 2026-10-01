extends Area2D
class_name Smasher

@export var tile_size: Vector2 = Vector2(128, 128)
@onready var smasher_size: Vector2 = Vector2(tile_size.x * 1.5, tile_size.y * 2.0)
@export var trigger_distance: float = 400.0
@export var fall_speed: float = 1800.0
@export var rise_speed: float = 300.0

var original_y: float
var state = "idle" # idle, falling, smashed, rising
var smashed_timer: float = 0.0
var player: Node2D = null
var _last_tex: Texture2D = null

var tex_normal = preload("res://assets/smasher_sharp/normal.png")
var tex_angry = preload("res://assets/smasher_sharp/angry.png")
var tex_hurt = preload("res://assets/smasher_sharp/hurt.png")
var sprite: Sprite2D = null

## The head (top) is a safe landing surface — only the bottom spikes crush.
## A body whose centre sits within this fraction of the height below the top
## edge counts as "standing on the head". Kept generous so a player settling
## onto the top (or clipping the upper side) is reliably spared; still well
## above the mid-body line so genuine crushes and side hits stay lethal.
const SAFE_TOP_FRACTION := 0.3

func _ready() -> void:
	original_y = global_position.y
	collision_layer = 2 # Detectable by spikes
	collision_mask = 1 | 2 # Player (1) and Enemies (2)
	
	var collision_shape = $CollisionShape2D
	if collision_shape and collision_shape.shape is RectangleShape2D:
		collision_shape.shape.size = Vector2(smasher_size.x * 0.8, smasher_size.y * 0.9)
	
	var raycast = $RayCast2D
	if raycast:
		raycast.target_position = Vector2(0, smasher_size.y / 2 + 10)
	
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered_smasher)

	if Global.gfx("enemy_sprites"):
		sprite = Sprite2D.new()
		sprite.texture = tex_normal
		if sprite.texture:
			var tex_size = sprite.texture.get_size()
			if tex_size.y > 0:
				var scale_y = smasher_size.y / tex_size.y
				sprite.scale = Vector2(scale_y, scale_y)
		add_child(sprite)
		queue_redraw()

	# Create one-way static top collision so player/enemies can land/stand on top safely
	var sb = StaticBody2D.new()
	sb.collision_layer = 1 # Solid floor/wall layer
	sb.collision_mask = 0
	var sb_coll = CollisionShape2D.new()
	var sb_rect = RectangleShape2D.new()
	sb_rect.size = Vector2(smasher_size.x * 0.8, 20)
	sb_coll.shape = sb_rect
	sb_coll.position = Vector2(0, -smasher_size.y / 2 + 10)
	sb_coll.one_way_collision = true
	sb_coll.one_way_collision_margin = 16.0
	sb.add_child(sb_coll)
	add_child(sb)

func _process(delta: float) -> void:
	if Global.debug_toggles.get("show_collisions", false):
		queue_redraw()
	if not player:
		# Find player dynamically
		var parent = get_parent()
		if Global.player:
			player =  Global.player
		#if parent and parent.has_node("Player"):
			#player = parent.get_node("Player")
		return
		
	match state:
		"idle":
			# Trigger if player is close horizontally and below the smasher
			if abs(global_position.x - player.global_position.x) < trigger_distance and global_position.y < player.global_position.y:
				state = "falling"
		"falling":
			global_position.y += fall_speed * delta
			var raycast = $RayCast2D
			if raycast and raycast.is_colliding():
				# Stop falling when hitting the floor
				var hit_point = raycast.get_collision_point()
				global_position.y = hit_point.y - smasher_size.y / 2
				state = "smashed"
				print("spike smashed")
				smashed_timer = 1.0
				if AudioManager.is_on_screen(global_position):
					AudioManager.play("new_hits", 0.0, 0.08)
		"smashed":
			smashed_timer -= delta
			if smashed_timer <= 0:
				state = "rising"
		"rising":
			global_position.y -= rise_speed * delta
			if global_position.y <= original_y:
				global_position.y = original_y
				state = "idle"

	if sprite and Global.gfx("enemy_sprites"):
		if state == "falling" or state == "smashed":
			if sprite.texture != tex_angry:
				sprite.texture = tex_angry
				if _last_tex != tex_angry:
					if AudioManager.is_on_screen(global_position):
						AudioManager.play("grunt", 0.0, 0.12)
		else:
			if sprite.texture != tex_normal:
				sprite.texture = tex_normal
				if _last_tex != tex_normal:
					if AudioManager.is_on_screen(global_position):
						AudioManager.play("grunt", -4.0, 0.12)
		_last_tex = sprite.texture

	# Continuous overlap check so a body already inside our box (not just one
	# entering this frame) is still crushed. The top is safe via the one-way
	# StaticBody2D + the standing-on-top guard inside _on_body_entered.
	if player and is_instance_valid(player) and monitoring:
		if not player.get("is_dead") and overlaps_body(player):
			_on_body_entered(player)

func _draw() -> void:
	if not Global.gfx("enemy_sprites") or not sprite or not sprite.texture:
		var half := smasher_size * 0.5
		var rect = Rect2(-half, smasher_size)
		var base_col := Color(0.28, 0.28, 0.34)
		var bevel_col := Color(0.42, 0.42, 0.50)
		var shadow_col := Color(0.18, 0.18, 0.22)
		var ink_col := Color(0.10, 0.10, 0.14)

		# 1. Main crushing block body
		draw_rect(rect, base_col, true)

		# 2. Bevel highlights & shadow
		draw_line(Vector2(-half.x, -half.y + 2), Vector2(half.x, -half.y + 2), bevel_col, 3.0)
		draw_line(Vector2(-half.x + 2, -half.y), Vector2(-half.x + 2, half.y), bevel_col, 3.0)
		draw_line(Vector2(half.x - 2, -half.y), Vector2(half.x - 2, half.y), shadow_col, 3.0)
		draw_rect(rect, ink_col, false, 2.5)

		# 3. Angry angled eyes with dark frame
		var eye_w := 28.0
		var eye_h := 16.0
		var eye_y := -10.0
		var eye_lx := -smasher_size.x * 0.25
		var eye_rx := smasher_size.x * 0.25

		# Eye sockets
		draw_rect(Rect2(eye_lx - eye_w * 0.5 - 2, eye_y - 2, eye_w + 4, eye_h + 4), ink_col, true)
		draw_rect(Rect2(eye_rx - eye_w * 0.5 - 2, eye_y - 2, eye_w + 4, eye_h + 4), ink_col, true)
		# Glowing red pupils
		draw_rect(Rect2(eye_lx - eye_w * 0.5, eye_y, eye_w, eye_h), Color(1.0, 0.15, 0.15), true)
		draw_rect(Rect2(eye_rx - eye_w * 0.5, eye_y, eye_w, eye_h), Color(1.0, 0.15, 0.15), true)
		# Inner pupil highlight
		draw_rect(Rect2(eye_lx - 2, eye_y + 4, 6, 8), Color(1.0, 0.8, 0.8), true)
		draw_rect(Rect2(eye_rx - 2, eye_y + 4, 6, 8), Color(1.0, 0.8, 0.8), true)

		# 4. Crushing teeth spikes on bottom
		var points = PackedVector2Array([
			Vector2(-half.x, half.y),
			Vector2(-half.x * 0.5, half.y + 22),
			Vector2(0, half.y),
			Vector2(half.x * 0.5, half.y + 22),
			Vector2(half.x, half.y)
		])
		draw_polygon(points, PackedColorArray([Color(0.85, 0.85, 0.90)]))
		draw_polyline(points, ink_col, 2.0)

	if Global.debug_toggles.get("show_collisions", false):
		draw_rect(Rect2(-smasher_size / 2, smasher_size), Color.GREEN, false, 2.0)

func _on_body_entered(body: Node2D) -> void:
	# Landing on top of the smasher is safe (handled by one-way StaticBody2D).
	# Check if the body's center is near the smasher top — if so, they're standing
	# on the head, which is never lethal (only the bottom spikes crush).
	var body_center_y = body.global_position.y
	var smasher_top_y = global_position.y - smasher_size.y / 2.0
	if body_center_y < smasher_top_y + smasher_size.y * SAFE_TOP_FRACTION:
		return

	if body is BaseEnemy:
		if state == "falling" or state == "smashed":
			body.die_torn(Vector2(0, fall_speed))
		else:
			body.die_torn(Vector2.ZERO)
		return

	# Player (or anything else with die()): defer to the parry system so the hit
	# can be parried (which launches the player UP and phases us out); otherwise
	# it's a lethal crush.
	if body.has_method("die"):
		_hit_player(body)

## Give the player a parry chance; if none is taken, crush them. Returns nothing.
func _hit_player(body: Node) -> void:
	if not body.has_method("die") or body.get("is_dead"):
		return
	# Just parried → phasing through, invulnerable. Smashers are not stompable
	# from the side/bottom; the safe top is handled by the caller's top guard.
	if body.has_method("is_parry_invuln") and body.is_parry_invuln():
		return
	body.die(false, "a smasher", true)

func die() -> void:
	if sprite and Global.gfx("enemy_sprites"):
		sprite.texture = tex_hurt
	TearEffect.apply(self, smasher_size, Color(0.3, 0.3, 0.4), Vector2.ZERO)
	queue_free()

func _on_area_entered_smasher(area: Area2D) -> void:
	if area.get_script() and area.get_script().resource_path.contains("spike"):
		die()
