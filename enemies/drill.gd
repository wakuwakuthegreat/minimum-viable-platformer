extends Area2D
class_name Drill

@export var tile_size: Vector2 = Vector2(128, 128)
@onready var drill_size: Vector2 = Vector2(tile_size.x * 1.2, tile_size.y * 1.5)
@export var trigger_distance: float = 400.0
@export var fall_speed: float = 600.0

var state = "idle"
var player: Node2D = null
var death_y_limit: float = 4000.0

var anim: AnimatedSprite2D = null
var _engine_player: AudioStreamPlayer = null

## The drill's head (top body) is a safe landing surface — only the lower
## pointed bit drills through things. A body whose centre sits within this
## fraction of the height below the top edge counts as standing on the head.
const SAFE_TOP_FRACTION := 0.3

## Built once and shared by every drill — see bomb.gd's _boom_frames for why
## per-instance load() of animation frames was a hitch on phones. Also spares
## every instance its own redundant load() of frame 0 just to read its size.
static var _drill_frames: SpriteFrames = null

static func _get_drill_frames() -> SpriteFrames:
	if _drill_frames != null: return _drill_frames
	var frames := SpriteFrames.new()
	frames.add_animation("drill")
	for f in range(6):
		var tex = load("res://assets/animations/mole/" + str(f) + ".png")
		if tex:
			frames.add_frame("drill", tex)
	frames.set_animation_speed("drill", 15.0)
	frames.set_animation_loop("drill", true)
	_drill_frames = frames
	return frames

## Preloaded once — was re-load()-ed from disk every time a drill started falling.
const ENGINE_SOUND := preload("res://assets/sounds/Engine.wav")

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2 # Layer 1 (Tiles, Player), Layer 2 (Enemies)
	body_entered.connect(_on_body_entered)
	
	# setup collision shape size dynamically
	var collision_shape = $CollisionShape2D
	if collision_shape and collision_shape.shape is RectangleShape2D:
		collision_shape.shape.size = drill_size

	# One-way static platform across the head so the player/enemies can land and
	# stand on top safely — only the pointed underside is lethal. Mirrors the
	# smasher's top guard so both crushers behave the same when landed on.
	var sb = StaticBody2D.new()
	sb.collision_layer = 1 # Solid floor/wall layer
	sb.collision_mask = 0
	var sb_coll = CollisionShape2D.new()
	var sb_rect = RectangleShape2D.new()
	sb_rect.size = Vector2(drill_size.x * 0.8, 20)
	sb_coll.shape = sb_rect
	sb_coll.position = Vector2(0, -drill_size.y / 2 + 10)
	sb_coll.one_way_collision = true
	sb_coll.one_way_collision_margin = 16.0
	sb.add_child(sb_coll)
	add_child(sb)

	if Global.gfx("enemy_sprites"):
		anim = AnimatedSprite2D.new()
		var frames := _get_drill_frames()
		anim.sprite_frames = frames

		# Prioritize aspect ratio of the 480x620 asset to fit collision footprint (drill_size), scaled up by 1.6x for sprite size
		var base_tex: Texture2D = frames.get_frame_texture("drill", 0) if frames.get_frame_count("drill") > 0 else null
		if base_tex:
			var tex_size = base_tex.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				anim.scale = (drill_size / tex_size) * 1.6
		else:
			anim.scale = Vector2(0.32, 0.31) * 1.6
			
		add_child(anim)
		anim.play("drill")

func _process(delta: float) -> void:
	if Global.debug_toggles.get("show_collisions", false):
		queue_redraw()

	if not player:
		var parent = get_parent()
		
		if Global.player:
			player =  Global.player
			
		#if parent and parent.has_node("Player"):
			#player = parent.get_node("Player")
			if player:
				death_y_limit = player.get("death_y_limit")
		return

	match state:
		"idle":
			if abs(global_position.x - player.global_position.x) < trigger_distance and global_position.y < player.global_position.y:
				state = "falling"
				_start_engine()
		"falling":
			global_position.y += fall_speed * delta
			if global_position.y > death_y_limit:
				_stop_engine()
				queue_free()
				return

	# Continuous overlap kill: catches a drill that started overlapping the player
	# while idle (body_entered only fires on the entering frame, so a drill that
	# begins its drop already inside the player would otherwise pass through).
	if player and is_instance_valid(player) and monitoring:
		if not player.get("is_dead") and overlaps_body(player):
			_hit_player(player)

func _start_engine() -> void:
	if not Global.is_unlocked("sfx"): return
	_engine_player = AudioStreamPlayer.new()
	_engine_player.stream = ENGINE_SOUND
	_engine_player.volume_db = -6.0
	_engine_player.pitch_scale = 1.0 + randf_range(-0.05, 0.05)
	_engine_player.finished.connect(func():
		if _engine_player and is_instance_valid(_engine_player) and state == "falling":
			_engine_player.play()
	)
	add_child(_engine_player)
	_engine_player.play()

func _stop_engine() -> void:
	if _engine_player and is_instance_valid(_engine_player):
		_engine_player.stop()
		_engine_player.queue_free()
		_engine_player = null

func _on_body_entered(body: Node) -> void:
	if body is TileObject:
		if state == "falling":
			_stop_engine()
			body.queue_free()
		return
	if body is BaseEnemy:
		if state == "falling":
			_stop_engine()
			body.die_torn(Vector2(0, fall_speed))
		return
	# Player (or anything else with die()). A drill is pointy all over — any
	# contact is lethal, whether it is idle or falling. The continuous poll in
	# _process is the primary path; this just catches the entering frame early.
	if body.has_method("die"):
		if state == "falling":
			_stop_engine()
		_hit_player(body)

## Kill the player unless they are mid-parry (invulnerable), or unless they are
## standing on the drill's head (the top is a safe surface — only the pointed
## underside drills). Drills are NOT stompable otherwise.
func _hit_player(body: Node) -> void:
	if not body.has_method("die") or body.get("is_dead"):
		return
	if _is_on_head(body):
		return
	if body.has_method("is_parry_invuln") and body.is_parry_invuln():
		return
	body.die(false, "a drill", true)

## True if the body's centre is near the drill's top edge (standing on the head).
func _is_on_head(body: Node) -> bool:
	var body_center_y: float = body.global_position.y
	var drill_top_y: float = global_position.y - drill_size.y / 2.0
	return body_center_y < drill_top_y + drill_size.y * SAFE_TOP_FRACTION

func _draw() -> void:
	if not Global.gfx("enemy_sprites") or not anim:
		# Draw a cool triangular/pointed drill shape so the user is wowed!
		# Top body
		draw_rect(Rect2(-drill_size.x / 2, -drill_size.y / 2, drill_size.x, drill_size.y * 0.4), Color(0.4, 0.4, 0.45))
		# Spinnable-looking yellow/black caution stripes on the body
		draw_rect(Rect2(-drill_size.x / 2, -drill_size.y / 2 + 10, drill_size.x, 15), Color(0.8, 0.7, 0.1))
		
		# Pointy tip (triangle) at the bottom
		var points = PackedVector2Array()
		points.append(Vector2(-drill_size.x / 2, -drill_size.y / 2 + drill_size.y * 0.4))
		points.append(Vector2(0, drill_size.y / 2))
		points.append(Vector2(drill_size.x / 2, -drill_size.y / 2 + drill_size.y * 0.4))
		draw_polygon(points, PackedColorArray([Color(0.6, 0.6, 0.65)]))
		
		# Draw screw threads (slanted lines)
		draw_line(Vector2(-drill_size.x / 2 + 10, -drill_size.y / 2 + drill_size.y * 0.4 + 10), Vector2(drill_size.x / 2 - 10, -drill_size.y / 2 + drill_size.y * 0.4 + 25), Color(0.3, 0.3, 0.3), 3.0)
		draw_line(Vector2(-drill_size.x / 3, -drill_size.y / 2 + drill_size.y * 0.4 + 25), Vector2(drill_size.x / 3, -drill_size.y / 2 + drill_size.y * 0.4 + 40), Color(0.3, 0.3, 0.3), 3.0)

	if Global.debug_toggles.get("show_collisions", false):
		draw_rect(Rect2(-drill_size.x / 2, -drill_size.y / 2, drill_size.x, drill_size.y), Color.GREEN, false, 2.0)
