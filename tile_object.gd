extends StaticBody2D
class_name TileObject

# --- EXPORTS ---
@export_category("Debug Settings")
## Toggles the custom visual drawing for hitboxes in the game
@export var debug: bool = false:
	set(value):
		debug = value
		queue_redraw()

@export_category("Sizing Controls")
## Set the uniform size footprint of this entire object (Scales sprite & solid collision)
@export var base_size: Vector2 = Vector2(128, 128):
	set(value):
		base_size = value
		if is_inside_tree(): update_sizes()

## Set the custom size footprint of the Area2D trigger zone
@export var trigger_zone_size: Vector2 = Vector2(140, 140):
	set(value):
		trigger_zone_size = value
		if is_inside_tree(): update_sizes()

@export_category("Visuals")
@export var visual_texture: Texture2D:
	set(value):
		visual_texture = value
		if is_inside_tree() and sprite:
			sprite.texture = value
			update_sizes()

# --- NODE REFERENCES ---
@onready var sprite: Sprite2D = $Sprite2D
@onready var solid_collision: CollisionShape2D = $CollisionShape2D
@onready var trigger_area: Area2D = $Area2D
@onready var area_collision: CollisionShape2D = $Area2D/CollisionShape2D

# --- JUICE VARIABLES ---
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _original_sprite_position: Vector2 = Vector2.ZERO

var expose_top: bool = false
var expose_bottom: bool = false
var expose_left: bool = false
var expose_right: bool = false

func _ready() -> void:
	if sprite:
		_original_sprite_position = sprite.position
		if visual_texture:
			sprite.texture = visual_texture
		sprite.show_behind_parent = true

	update_sizes()
	queue_redraw()
	
	if false:#get_tree():
		await get_tree().process_frame
		determine_exposed_sides()

func _process(delta: float) -> void:
	if Global.debug_toggles.get("show_collisions", false):
		queue_redraw()
	if _shake_timer > 0:
		_shake_timer -= delta
		sprite.position = _original_sprite_position + Vector2(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity)
		)
		if _shake_timer <= 0:
			sprite.position = _original_sprite_position

# --- SIZING FUNCTIONS ---

## Dynamically adjusts the sprite scaling and collision shapes to match specified sizes
func update_sizes() -> void:
	if not sprite or not solid_collision or not area_collision:
		return

	if Global.use_primitives:
		sprite.visible = false
	else:
		sprite.visible = true

	# Scale Sprite to fit base_size if a texture is set
	if sprite.texture and not Global.use_primitives:
		var tex_size = sprite.texture.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			sprite.scale = base_size / tex_size

	# Solid Collision (RectangleShape2D)
	if not solid_collision.shape:
		solid_collision.shape = RectangleShape2D.new()
	if solid_collision.shape is RectangleShape2D:
		solid_collision.shape.size = base_size

	# Area2D Trigger Collision (RectangleShape2D)
	if not area_collision.shape:
		area_collision.shape = RectangleShape2D.new()
	if area_collision.shape is RectangleShape2D:
		area_collision.shape.size = trigger_zone_size

	queue_redraw()

# --- JUICE / ANIMATION FUNCTIONS ---

func squash(squish_factor: Vector2 = Vector2(1.3, 0.7), duration: float = 0.15) -> void:
	if not sprite: return
	var normal_scale = Vector2.ONE
	if sprite.texture:
		normal_scale = base_size / sprite.texture.get_size()
	var squished_scale = normal_scale * squish_factor
	
	var squished_offset_y = base_size.y * 0.5 * (1.0 - squish_factor.y)
	
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "scale", squished_scale, duration)
	tween.parallel().tween_property(sprite, "position:y", _original_sprite_position.y + squished_offset_y, duration)
	
	tween.tween_property(sprite, "scale", normal_scale, duration * 1.5)
	tween.parallel().tween_property(sprite, "position:y", _original_sprite_position.y, duration * 1.5)

func shake(intensity: float = 8.0, duration: float = 0.3) -> void:
	_shake_intensity = intensity
	_shake_timer = duration

func determine_exposed_sides() -> void:
	expose_top = true
	expose_bottom = true
	expose_left = true
	expose_right = true
	
	var tiles = get_tree().get_nodes_in_group("solid_tiles")
	for tile in tiles:
		if tile == self or not tile is TileObject: continue
		var diff = tile.global_position - global_position
		# Top adjacent block check
		if abs(diff.x) < 2.0 and abs(diff.y + base_size.y) < 2.0:
			expose_top = false
		# Bottom adjacent block check
		if abs(diff.x) < 2.0 and abs(diff.y - base_size.y) < 2.0:
			expose_bottom = false
		# Left adjacent block check
		if abs(diff.x + base_size.x) < 2.0 and abs(diff.y) < 2.0:
			expose_left = false
		# Right adjacent block check
		if abs(diff.x - base_size.x) < 2.0 and abs(diff.y) < 2.0:
			expose_right = false
	
	queue_redraw()

# --- DRAWING ---
# Always draw a coloured placeholder rectangle so tiles are visible
# even without a texture assigned. Debug mode adds extra outlines.
func _draw() -> void:
	var half = base_size * 0.5

	if not visual_texture or Global.use_primitives:
		# Polished architectural stone slab look
		var fill_rect = Rect2(-half, base_size)
		var base_stone := Color(0.33, 0.31, 0.28)
		var cap_stone  := Color(0.42, 0.39, 0.35)
		var seam_col   := Color(0.24, 0.22, 0.20)
		var hi_col     := Color(0.62, 0.58, 0.52)
		var shadow_col := Color(0.18, 0.16, 0.14)

		# 1. Main slab body
		draw_rect(fill_rect, base_stone, true)

		# 2. Top cap slab band (18px)
		var cap_h = min(18.0, base_size.y * 0.25)
		draw_rect(Rect2(-half.x, -half.y, base_size.x, cap_h), cap_stone, true)

		# 3. Top edge bevel highlight & cap seam line
		draw_line(-half, Vector2(half.x, -half.y), hi_col, 2.0)
		draw_line(Vector2(-half.x, -half.y + cap_h), Vector2(half.x, -half.y + cap_h), seam_col, 1.5)

		# 4. Base shadow
		var shadow_h = min(12.0, base_size.y * 0.15)
		draw_rect(Rect2(-half.x, half.y - shadow_h, base_size.x, shadow_h), shadow_col, true)

		# 5. Crisp border
		draw_rect(fill_rect, seam_col, false, 2.0)

	# Highlight lines on exposed outside edges (based on 4px thick lines on 160x160 assets)
	var line_thickness = 4.0 * (base_size.y / 160.0)
	var highlight_color = Color.BLACK
	
	if expose_top:
		draw_line(Vector2(-half.x, -half.y), Vector2(half.x, -half.y), highlight_color, line_thickness)
	if expose_bottom:
		draw_line(Vector2(-half.x, half.y), Vector2(half.x, half.y), highlight_color, line_thickness)
	if expose_left:
		draw_line(Vector2(-half.x, -half.y), Vector2(-half.x, half.y), highlight_color, line_thickness)
	if expose_right:
		draw_line(Vector2(half.x, -half.y), Vector2(half.x, half.y), highlight_color, line_thickness)

	if debug:
		# Blue: solid physics box
		var solid_rect = Rect2(-half, base_size)
		draw_rect(solid_rect, Color(0, 0.5, 1, 0.7), false, 2.0)
		draw_rect(solid_rect, Color(0, 0.5, 1, 0.15), true)
		# Green: trigger area box
		var trigger_half = trigger_zone_size * 0.5
		var trigger_rect = Rect2(-trigger_half, trigger_zone_size)
		draw_rect(trigger_rect, Color(0, 1, 0.4, 0.7), false, 2.0)
		draw_rect(trigger_rect, Color(0, 1, 0.4, 0.1), true)

	if Global.debug_toggles.get("show_collisions", false):
		draw_rect(Rect2(-half, base_size), Color.GREEN, false, 2.0)
