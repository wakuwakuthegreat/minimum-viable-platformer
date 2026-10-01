extends StaticBody2D
class_name TileStrip

## Efficient single-StaticBody2D representation for a contiguous run of N tiles.
##
## Position convention (matches original per-tile spawn):
##   strip.position == centre of the FIRST surface tile in the run.
##   Collision shape sits below the surface row and extends `depth_tiles` rows deep.

@export var tile_size: Vector2 = Vector2(128, 128)
@export var length_tiles: int = 1
@export var depth_tiles: int = 8
@export var drawn_style: bool = true

## When true, foliage tufts are suppressed (used for elevated/floating platforms).
var no_foliage: bool = false

## Set by level_generator after all strips are placed: suppress side outline on that edge.
var left_neighbor: bool = false
var right_neighbor: bool = false

var _col_shape: CollisionShape2D
var _visual: Node2D

var _strip_color_top := Color(0.85, 0.92, 0.45)
var _strip_color_grass := Color(0.60, 0.78, 0.32)
var _strip_color_grass_dark := Color(0.36, 0.50, 0.20)
var _strip_color_earth_top := Color(0.96, 0.78, 0.50)
var _strip_color_earth_bot := Color(0.74, 0.50, 0.34)
var _strip_color_ink := Color(0.18, 0.14, 0.10)

func _ready() -> void:
	add_to_group("solid_tiles")
	collision_layer = 1
	collision_mask  = 0

	drawn_style = Global.is_unlocked("drawn_floors")
	_apply_palette()

	_col_shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(length_tiles * tile_size.x, depth_tiles * tile_size.y)
	_col_shape.shape = rect
	# Shape is centred. Strip.position is the centre of the FIRST surface tile,
	# so move the centre to (cols*tile/2 - tile/2,  depth*tile/2 - tile/2).
	_col_shape.position = Vector2(
		(length_tiles - 1) * tile_size.x * 0.5,
		(depth_tiles - 1) * tile_size.y * 0.5
	)
	add_child(_col_shape)

	_visual = Node2D.new()
	_visual.set_script(preload("res://tile_strip_visual.gd"))
	# Shift the visual so its local origin is the TOP-LEFT of the strip's
	# surface tile. A small extra upward offset makes the surface art read
	# as slightly raised above the collision plane (graphic only).
	_visual.position = Vector2(-tile_size.x * 0.5, -tile_size.y * 0.5 - 6.0)
	# Draw below all hazards (spikes, enemies, the player) so the grass
	# never clips over the surface entities.
	_visual.z_index = -10
	# CRITICAL: set owner_strip BEFORE add_child so the visual's _ready can
	# build its geometry on first frame.
	_visual.set("owner_strip", self)
	add_child(_visual)

func get_world_width() -> float:
	return length_tiles * tile_size.x

func _apply_palette() -> void:
	match Global.color_palette:
		"warm":
			_strip_color_earth_top = Color(1.00, 0.85, 0.55)
			_strip_color_earth_bot = Color(0.85, 0.55, 0.35)
			_strip_color_grass      = Color(0.70, 0.85, 0.35)
			_strip_color_grass_dark = Color(0.45, 0.58, 0.22)
			_strip_color_top        = Color(0.90, 0.95, 0.50)
		"cool":
			_strip_color_earth_top = Color(0.65, 0.78, 0.95)
			_strip_color_earth_bot = Color(0.45, 0.55, 0.75)
			_strip_color_grass      = Color(0.35, 0.70, 0.85)
			_strip_color_grass_dark = Color(0.22, 0.48, 0.60)
			_strip_color_top        = Color(0.75, 0.92, 0.95)
		"night":
			_strip_color_earth_top = Color(0.30, 0.28, 0.40)
			_strip_color_earth_bot = Color(0.18, 0.16, 0.25)
			_strip_color_grass      = Color(0.20, 0.45, 0.30)
			_strip_color_grass_dark = Color(0.12, 0.28, 0.20)
			_strip_color_top        = Color(0.30, 0.60, 0.40)
		"neon":
			_strip_color_earth_top = Color(0.10, 0.08, 0.18)
			_strip_color_earth_bot = Color(0.05, 0.04, 0.12)
			_strip_color_grass      = Color(0.00, 0.90, 0.50)
			_strip_color_grass_dark = Color(0.00, 0.55, 0.30)
			_strip_color_top        = Color(0.50, 1.00, 0.20)
			_strip_color_ink        = Color(0.80, 0.00, 0.90)

func refresh_visual() -> void:
	if _visual:
		_visual.queue_redraw()

func squash(squish_factor: Vector2 = Vector2(1.0, 0.85), duration: float = 0.12) -> void:
	# Tied to the general "Squash & Stretch" juice unlock now that tile_bounce is gone.
	if not Global.is_unlocked("juice_squash"): return
	if not _visual: return
	var tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", squish_factor, duration)
	tw.tween_property(_visual, "scale", Vector2.ONE, duration * 1.6).set_trans(Tween.TRANS_BACK)
