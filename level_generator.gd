extends Node2D

static var current_seed: int = 0

var rng = RandomNumberGenerator.new()

@export var tile_scene: PackedScene = preload("res://tile_object.tscn")
@export var tile_strip_scene: PackedScene = preload("res://tile_strip.tscn")
@export var player_scene: PackedScene = preload("res://player.tscn")
@export var spike_scene: PackedScene = preload("res://spike.tscn")
@export var smasher_scene: PackedScene = preload("res://smasher.tscn")
@export var ramp_scene: PackedScene = preload("res://ramp.tscn")
@export var ui_scene: PackedScene = preload("res://ui.tscn")
@export var bg_scene: PackedScene = preload("res://game_bg.tscn")
@export var hud_scene: PackedScene = preload("res://hud.tscn")
@export var pause_scene: PackedScene = preload("res://pause_menu.tscn")
@export var coin_scene: PackedScene = preload("res://coin.tscn")
@export var tile_size: Vector2 = Vector2(128, 128)

@export var frog_scene: PackedScene = preload("res://enemies/frog.tscn")
@export var big_frog_scene: PackedScene = preload("res://enemies/big_frog.tscn")
@export var bat_scene: PackedScene = preload("res://enemies/bat.tscn")
@export var bomb_scene: PackedScene = preload("res://enemies/bomb.tscn")
@export var rock_scene: PackedScene = preload("res://enemies/rock.tscn")
@export var kobold_scene: PackedScene = preload("res://enemies/kobold.tscn")
@export var shooter_scene: PackedScene = preload("res://enemies/shooter.tscn")
@export var drill_scene: PackedScene = preload("res://enemies/drill.tscn")
@export var jumper_scene: PackedScene = preload("res://enemies/jumper.tscn")

# ─── FEATURE GATES PER PATTERN CHARACTER ────────────────────────────────
# Maps an entity id (the value side of TEMPLATES' character dict) to the
# unlock feature key required for it to actually appear in-game.
const ENTITY_GATES := {
	"spike":     "",                  # always allowed
	"frog":      "enemies_basic",
	"kobold":    "enemies_basic",
	"bat":       "enemies_more",
	"big_frog":  "enemies_more",
	"bomb":      "enemies_advanced",
	"shooter":   "enemies_advanced",
	"drill":     "enemies_advanced",
	"jumper":    "enemies_advanced",
	"rock":      "enemies_advanced",
	"smasher":   "enemies_advanced",
}

const TEMPLATE_STARTER_IDX := 0

# Full template library (same as before).
var TEMPLATES: Array = [
	# 0 — safe start (always available)
	{ "pattern": ["................", "................", "################"] },

	# Flat runs
	{ "pattern": ["........", "........", "########"] },
	{ "pattern": ["............", "............", "############"] },

	# Simple pits
	{ "pattern": ["........", "........", "##aaaa##"] },
	{ "pattern": ["........", "........", "###aa###"] },
	{ "pattern": [".........", ".........", "####a####"] },

	# Spikes
	{ "pattern": ["........", "........", "..s.s.s.", "########"], "s": "spike" },
	{ "pattern": ["........", "........", "s.....s.", "########"], "s": "spike" },
	{ "pattern": ["............", "............", "s..s....s..s", "############"], "s": "spike" },

	# Spikes over pit
	{ "pattern": ["............", "............", "##s.aaaa.s##"], "s": "spike" },
	{ "pattern": ["............", "............", "##.s.aa.s.##"], "s": "spike" },

	# Stairs
	{ "pattern": ["......##", "....####", "..######", "########"] },
	{ "pattern": ["##......", "####....", "######..", "########"] },
	{ "pattern": ["....##..", "..######", "########"] },
	{ "pattern": ["..####..", "########"] },

	# Elevated platform
	{ "pattern": ["...####.", "........", "........", "########"] },
	{ "pattern": ["..####..", "........", "........", "########"] },
	{ "pattern": ["....##.....", "...........", "...........", "###########"] },

	# Smashers
	{ "pattern": ["....T.....", "..........", "..........", "..........", "##########"], "T": "smasher" },
	{ "pattern": [".T.......T...", "..............", ".............", ".............", "#############"], "T": "smasher" },
	{ "pattern": ["....T...", "........", "........", "##....##", "########"], "T": "smasher" },
	{ "pattern": ["..T.....", "........", "........", "..s.s.s.", "########"], "T": "smasher", "s": "spike" },

	# Frogs
	{ "pattern": ["........", "........", "....f...", "########"], "f": "frog" },
	{ "pattern": ["........", "........", ".f....f.", "########"], "f": "frog" },
	{ "pattern": ["........", "........", "...f....", "..####..", "........", "########"], "f": "frog" },
	{ "pattern": ["............", "............", "f....f....f.", "############"], "f": "frog" },

	# Big frog
	{ "pattern": ["........", "........", "....F...", "########"], "F": "big_frog" },
	{ "pattern": ["............", "............", "....F.......", "############"], "F": "big_frog" },

	# Bats
	{ "pattern": ["..b.....", "........", "........", "########"], "b": "bat" },
	{ "pattern": [".b....b.", "........", "........", "########"], "b": "bat" },
	{ "pattern": ["....b...", "........", "##aaaa##"], "b": "bat" },
	{ "pattern": ["...b...b...", "...........", "###.aaaa.##"], "b": "bat" },

	# Bombs
	{ "pattern": ["........", "........", "......B.", "########"], "B": "bomb" },
	{ "pattern": ["........", "........", "...B....", "########"], "B": "bomb" },
	{ "pattern": ["........", "........", "B......B", "########"], "B": "bomb" },

	# Rock springs
	{ "pattern": ["............", "............", ".....r......", "############"], "r": "rock" },
	{ "pattern": ["............", "............", ".....r......", "##aaaaaa####"], "r": "rock" },

	# Shooters
	{ "pattern": ["........", "........", "........", "...S....", "########"], "S": "shooter" },
	{ "pattern": ["........", "........", "S.......", "........", "########"], "S": "shooter" },
	{ "pattern": ["............", "............", "............", ".......S....", "############"], "S": "shooter" },

	# Kobold patrols
	{ "pattern": ["........", "........", "..k.....", ".######."], "k": "kobold" },
	{ "pattern": ["........", "........", ".k....k.", "########"], "k": "kobold" },
	{ "pattern": ["....####", "........", ".k......", "########"], "k": "kobold" },

	# Combos
	{ "pattern": ["....b...", "........", "..k.....", "########"], "b": "bat", "k": "kobold" },
	{ "pattern": ["........", "........", ".f....B.", "########"], "f": "frog", "B": "bomb" },
	{ "pattern": ["............", "............", "s.f.s...s.f.", "############"], "s": "spike", "f": "frog" },
	{ "pattern": [".b.......b..", "............", "###.aaaa.###"], "b": "bat" },
	{ "pattern": ["....b...", "........", ".k..s.k.", "########"], "b": "bat", "k": "kobold", "s": "spike" },
	{ "pattern": ["............", ".b.......b..", "............", "s...s...s...", "############"], "b": "bat", "s": "spike" },

	# Drill & jumper
	{ "pattern": ["..d.....", "........", "........", "........", "########"], "d": "drill" },
	{ "pattern": [".d.......d...", "..............", ".............", ".............", "#############"], "d": "drill" },
	{ "pattern": ["........", "........", "....j...", "########"], "j": "jumper" },
	{ "pattern": ["........", "........", ".j....j.", "########"], "j": "jumper" },

	# ═══════════════════════════════════════════════════════════════════
	# MORE PROCGEN  (gate: more_procgen) — all horizontal, chain anywhere.
	# Edge columns stay clear above the ground row so left/right stitching
	# always locks onto the ground level.
	# ═══════════════════════════════════════════════════════════════════
	{ "pattern": ["................", "................", "................", "################"], "gate": "more_procgen" },
	{ "pattern": ["...####..####...", "................", "................", "################"], "gate": "more_procgen" },
	{ "pattern": ["....##....##....", "...####..####...", "................", "################"], "gate": "more_procgen" },
	{ "pattern": ["................", "................", "..s..s..s..s..s.", "################"], "gate": "more_procgen", "s": "spike" },
	{ "pattern": ["................", "......####......", "................", "####aaaaaa######"], "gate": "more_procgen" },
	{ "pattern": ["................", "................", ".f..b...k....B..", "################"], "gate": "more_procgen", "f": "frog", "b": "bat", "k": "kobold", "B": "bomb" },
	{ "pattern": ["................", "................", "...s......s.....", "##aa######aa####"], "gate": "more_procgen", "s": "spike" },
	{ "pattern": ["................", ".....s..s.......", "....######......", "################"], "gate": "more_procgen", "s": "spike" },
	{ "pattern": ["................", "...##.....##....", "......####......", "################"], "gate": "more_procgen" },
	{ "pattern": ["................", "................", "f...k...b...j...", "################"], "gate": "more_procgen", "f": "frog", "k": "kobold", "b": "bat", "j": "jumper" },
	{ "pattern": ["................", "....####...####.", "................", "..s..s..s..s..s.", "################"], "gate": "more_procgen", "s": "spike" },
	{ "pattern": ["................", "................", "....########....", "################"], "gate": "more_procgen" },
	{ "pattern": ["................", "................", "...B......B.....", "################"], "gate": "more_procgen", "B": "bomb" },
	{ "pattern": ["................", "..S.........S...", "................", "################"], "gate": "more_procgen", "S": "shooter" },

	# ── Extra creative sections (gate: more_procgen) ─────────────────────────
	# All 16 wide with clear left/right edge columns above the ground row so they
	# stitch onto flat ground from either side.
	# Twin sky platforms patrolled by bats.
	{ "pattern": ["................", "...####..####...", ".b..........b...", "................", "################"], "gate": "more_procgen", "b": "bat" },
	# Spike gauntlet with a mid-air rest platform.
	{ "pattern": ["................", "......####......", "................", ".s.s.s..s.s.s.s.", "################"], "gate": "more_procgen", "s": "spike" },
	# Parry corridor: two bombs flanking a kobold.
	{ "pattern": ["................", "................", "...B....k....B..", "################"], "gate": "more_procgen", "B": "bomb", "k": "kobold" },
	# Floating ascending stepping-stones.
	{ "pattern": [".............##.", "..........##....", ".......##.......", "....##..........", "################"], "gate": "more_procgen" },
	# Drill dropping into a jump-the-gap pit.
	{ "pattern": ["................", "................", "......d.........", "###aaaaaaaa#####"], "gate": "more_procgen", "d": "drill" },
	# Kobolds patrolling a raised deck over a spike bed.
	{ "pattern": ["....k......k....", "....########....", "................", "..s..s..s..s..s.", "################"], "gate": "more_procgen", "k": "kobold", "s": "spike" },
	# Bumpy mogul ground (coin-friendly).
	{ "pattern": ["................", "................", "..##..##..##..#.", "################"], "gate": "more_procgen" },
	# Twin shooters covering an open lane.
	{ "pattern": ["................", "................", "...S........S...", "................", "################"], "gate": "more_procgen", "S": "shooter" },
	# Big frog and a bomb sharing an arena.
	{ "pattern": ["................", "................", ".....F......B...", "################"], "gate": "more_procgen", "F": "big_frog", "B": "bomb" },
	# Zig-zag ledges with a frog underneath.
	{ "pattern": ["................", "..###.....###...", ".......f........", "................", "################"], "gate": "more_procgen", "f": "frog" },
	# Smasher hallway — time the run between two crushers.
	{ "pattern": ["...T......T.....", "................", "................", "................", "################"], "gate": "more_procgen", "T": "smasher" },
	# Bat-guarded stepping platforms.
	{ "pattern": ["................", "....##....##....", "...b........b...", "................", "################"], "gate": "more_procgen", "b": "bat" },

	# ═══════════════════════════════════════════════════════════════════
	# VERTICAL SECTIONS  (gate: vertical_sections)
	# The world auto-runs the player rightward, so these are shaped so the
	# player is FORCED to change elevation as they cross:
	#   • vertical_up  — an ascending staircase. Steps are exactly 1 tile tall
	#     with wide (3–5 tile) treads so a single jump clears each riser while
	#     the run momentum carries the player forward and up. The block ends
	#     higher than it began, so `next_y` (the base spawn row for the next
	#     section) moves UP.
	#   • vertical_down — a descending staircase. The floor falls away one tile
	#     at a time, so the player simply drops to each lower tread. `next_y`
	#     moves DOWN.
	# Every column is solid from its tread down to the block floor, so nobody
	# falls into a void and the death floor (get_local_lowest_y in player.gd)
	# tracks the new elevation automatically.
	# ═══════════════════════════════════════════════════════════════════

	# VU-a — gentle climb (up 2), 4-wide treads. Easiest riser; follows flat
	# ground or a recovery after a drop, hands off to anything.
	{ "pattern": ["........####", "....########", "############"],
	  "gate": "vertical_sections", "type": "vertical_up",
	  "allow_prev": ["horizontal", "vertical_down"], "allow_next": ["any"] },

	# VU-b — climb (up 3), 3-wide treads. May crest into any vertical (another
	# climb, or a drop that turns the top into a peak).
	{ "pattern": [".........###", "......######", "...#########", "############"],
	  "gate": "vertical_sections", "type": "vertical_up",
	  "allow_prev": ["horizontal"], "allow_next": ["horizontal", "any_vertical"] },

	# VU-c — long gentle climb (up 2), 5-wide treads. Very forgiving; follows
	# anything, hands off to flat.
	{ "pattern": ["..........#####", ".....##########", "###############"],
	  "gate": "vertical_sections", "type": "vertical_up",
	  "allow_prev": ["any"], "allow_next": ["horizontal"] },

	# VD-a — gentle drop (down 2), 4-wide treads. Follows anything, hands off
	# to anything.
	{ "pattern": ["####........", "########....", "############"],
	  "gate": "vertical_sections", "type": "vertical_down",
	  "allow_prev": ["any"], "allow_next": ["any"] },

	# VD-b — drop (down 3), 3-wide treads. May bottom out into any vertical (a
	# deeper drop, or a climb that turns the base into a valley).
	{ "pattern": ["###.........", "######......", "#########...", "############"],
	  "gate": "vertical_sections", "type": "vertical_down",
	  "allow_prev": ["horizontal", "vertical_up"], "allow_next": ["horizontal", "any_vertical"] },

	# VD-c — deep drop (down 4), 3-wide treads. Only after flat; hands off to flat.
	{ "pattern": ["###............", "######.........", "#########......", "############...", "###############"],
	  "gate": "vertical_sections", "type": "vertical_down",
	  "allow_prev": ["horizontal"], "allow_next": ["horizontal"] },
]

# Templates available BEFORE procgen is unlocked.
const PRE_PROCGEN_INDICES := [0, 1, 6, 7, 4]
# index 0 = safe start, 1/4 = flat / pit, 6/7 = spike rows

var player: Node = null
var dirt_tex = preload("res://assets/dirt_floor.png")
var top_dirt_tex = preload("res://assets/top_dirt_floor.png")
var _max_y: float = 0.0

# ─── ENDLESS STREAMING STATE ────────────────────────────────────────────
# The level is no longer a fixed run of `level_width_blocks` sections. Blocks are
# emitted one at a time, always in ascending index order off the single seeded
# `rng`, so the Nth block a seed produces is the same block whether it was built
# at load time or forty seconds into the run — seeds stay reproducible forever.
# Blocks behind the player are freed; the sequence is never rewound, so nothing
# is ever regenerated and the RNG never has to be replayed.

## Blocks built up front, before the player moves.
const PRIME_BLOCKS := 14
## Keep generating while the built edge is less than this far ahead of the player.
const GEN_AHEAD_PX := 4200.0
## Free a block once its right edge is this far behind the player.
const CULL_BEHIND_PX := 3000.0
## Most blocks generated in a single frame, so a long teleport (or the first
## post-spawn frame) can't stall on a hundred sections at once.
const MAX_BLOCKS_PER_FRAME := 3

## Rows the player can reliably gain in one jump. jumpMagnitude is 900 px/s with
## a 900 px/s² rise, so the apex is ~450 px ≈ 3.5 tiles — but they also have to
## land ON the ledge, so treat anything above 3 tiles as a wall.
const MAX_CLIMB_TILES := 3
## Longest run of ground that gets spiked when it dead-ends into such a wall.
const POCKET_SPIKE_MAX := 10

## One entry per live block: { "parent": Node2D, "end_x": float }.
var _blocks: Array = []
## Cursor state carried between blocks so streaming picks up exactly where the
## previous section left off.
var _next_x: int = 0
var _next_y: int = 0
var _block_index: int = 0
var _prev_type: String = "horizontal"
var _prev_allow_next: Array = ["any"]
var _active_indices: Array = []
## Strips from the most recent block, kept so the next block can be outline-linked
## across the seam without re-walking every strip in the world.
var _seam_strips: Array = []
## grid_x -> grid row of the topmost solid tile in that column. Used to spike
## pockets the auto-runner cannot climb out of. Trimmed along with the blocks.
var _floor_profile: Dictionary = {}
var _profile_min_x: int = 0
## Columns that already carry a pocket spike, so overlapping traps don't stack.
var _spiked_cols: Dictionary = {}
## Node the current block's content is parented to, so culling is one queue_free.
var _chunk_parent: Node2D = null
var _streaming: bool = false
var _cam: Camera2D = null

func _ready() -> void:
	# Reset the per-run distance counter so token awards stay correct.
	Global.last_run_distance = 0
	generate_level()
	setup_camera()
	# Show the first-time tutorial overlay before the player can move.
	# tutorial_screen.gd emits `finished` when the player taps through all
	# slides, at which point the game is fully live.
	if not Global.tutorial_seen:
		var tscript = preload("res://tutorial_screen.gd")
		var tut = tscript.new()
		add_child(tut)
	else:
		# Ambient run-start scenes (e.g. "you've been away a while").
		var scene: Dictionary = StoryDB.pending("run_start")
		if not scene.is_empty():
			var cut = preload("res://story_cut.gd").new()
			get_tree().root.add_child(cut)
			cut.play(scene.get("blocks", []), String(scene.get("mode", "black")))
			StoryDB.mark_seen(scene)


## Parent block content under the current chunk node so culling a section is a
## single queue_free. Falls back to the generator itself outside generation.
func _attach(n: Node) -> void:
	if _chunk_parent != null and is_instance_valid(_chunk_parent):
		_chunk_parent.add_child(n)
	else:
		add_child(n)


# ─── COIN PATTERNED PLACEMENT ───────────────────────────────────────────

## Returns true if (tx, ty) in the block pattern is a valid coin cell:
##   • The cell is empty (.)
##   • Not inside a 3-tile-deep strip from a '#' 1–2 rows above
##   • Has a '#' floor at least 2 rows below
func _coin_valid(pattern: Array, block_w: int, block_h: int, tx: int, ty: int) -> bool:
	if tx < 0 or tx >= block_w or ty < 0 or ty >= block_h: return false
	if pattern[ty][tx] != '.': return false
	for ty_above in range(max(0, ty - 2), ty):
		if pattern[ty_above][tx] == '#': return false
	for yy in range(ty + 1, block_h):
		if pattern[yy][tx] == '#':
			return (yy - ty) >= 2
	return false

## Place a coin at grid cell (tx, ty) within the current block.
func _place_coin(tx: int, ty: int, next_x: int, y_offset: int) -> void:
	var cp := coin_scene.instantiate()
	cp.position = Vector2(
		(next_x + tx) * tile_size.x + tile_size.x * 0.5,
		(y_offset + ty) * tile_size.y + tile_size.y * 0.5
	)
	_attach(cp)

## Coin pattern constants — tune these to adjust feel.
const COIN_ARC_HEIGHT    := 2.5   # rows of clearance at the peak of an arc
const COIN_LINE_CHANCE   := 0.55  # probability of picking arc vs diagonal vs cluster
const COIN_SKIP_CHANCE   := 0.45  # per-block chance of no coins at all (raised to reduce clutter)

## Place coins in one of several patterns (arc, diagonal, cluster, double-arc).
## Chosen per-block using the seeded rng so the same seed always produces the same layout.
func _spawn_coins_patterned(pattern: Array, block_w: int, block_h: int,
		next_x: int, y_offset: int) -> void:
	if rng.randf() < COIN_SKIP_CHANCE: return

	# Build a per-column floor profile: lowest row with '#' above the abyss.
	var floor_row: Array = []
	for tx in block_w:
		var fr := -1
		for ty in range(block_h - 1, -1, -1):
			if pattern[ty][tx] == '#':
				fr = ty; break
		floor_row.append(fr)

	var roll := rng.randf()

	if roll < 0.30:
		# ── Arc: sine curve above the floor ──────────────────────────────────
		for tx in block_w:
			if floor_row[tx] < 0: continue
			var arc_t = float(tx) / max(1, block_w - 1)
			var arc_lift = int(round(sin(arc_t * PI) * COIN_ARC_HEIGHT))
			var ty = floor_row[tx] - 2 - arc_lift
			if _coin_valid(pattern, block_w, block_h, tx, ty):
				_place_coin(tx, ty, next_x, y_offset)

	elif roll < 0.55:
		# ── Double arc: two offset sine waves, every-other column to thin out ─
		for tx in range(0, block_w, 2):  # every-other column keeps density manageable
			if floor_row[tx] < 0: continue
			for wave in [0.0, PI]:
				var arc_t = float(tx) / max(1, block_w - 1)
				var arc_lift := int(round(sin(arc_t * PI + wave) * COIN_ARC_HEIGHT * 0.6))
				var ty = floor_row[tx] - 2 - arc_lift
				if _coin_valid(pattern, block_w, block_h, tx, ty):
					_place_coin(tx, ty, next_x, y_offset)

	elif roll < 0.72:
		# ── Diagonal line: coins at a height that shifts left-to-right ───────
		var start_lift := rng.randi_range(1, 3)
		var end_lift   := rng.randi_range(1, 3)
		for tx in block_w:
			if floor_row[tx] < 0: continue
			var t = float(tx) / max(1, block_w - 1)
			var lift := int(round(lerp(float(start_lift), float(end_lift), t)))
			var ty = floor_row[tx] - 2 - lift
			if _coin_valid(pattern, block_w, block_h, tx, ty):
				_place_coin(tx, ty, next_x, y_offset)

	elif roll < 0.87:
		# ── Clusters: 2–3 vertical stacks of 2–3 coins ───────────────────────
		var n_clusters := rng.randi_range(1, 3)
		for _c in n_clusters:
			var tx := rng.randi_range(0, block_w - 1)
			if floor_row[tx] < 0: continue
			var height := rng.randi_range(2, 3)
			for k in height:
				var ty = floor_row[tx] - 2 - k
				if _coin_valid(pattern, block_w, block_h, tx, ty):
					_place_coin(tx, ty, next_x, y_offset)

	else:
		# ── Row: coins at a fixed height, every 3rd column for breathing room ─
		var lift := rng.randi_range(2, 4)
		for tx in range(0, block_w, 3):  # every-3rd column (was every-2nd)
			if floor_row[tx] < 0: continue
			var ty = floor_row[tx] - lift
			if _coin_valid(pattern, block_w, block_h, tx, ty):
				_place_coin(tx, ty, next_x, y_offset)

# ─── ENTITY SPAWNING ────────────────────────────────────────────────────

func _is_entity_allowed(entity_id: String) -> bool:
	var gate: String = ENTITY_GATES.get(entity_id, "")
	if gate == "":
		return true
	return Global.is_unlocked(gate)

func _spawn_entity(id: String, world_pos: Vector2) -> void:
	if not _is_entity_allowed(id):
		return
	var inst = null
	match id:
		"smasher":  inst = smasher_scene.instantiate()
		"frog":     inst = frog_scene.instantiate()
		"big_frog": inst = big_frog_scene.instantiate()
		"bat":      inst = bat_scene.instantiate()
		"bomb":     inst = bomb_scene.instantiate()
		"rock":     inst = rock_scene.instantiate()
		"kobold":   inst = kobold_scene.instantiate()
		"shooter":  inst = shooter_scene.instantiate()
		"drill":    inst = drill_scene.instantiate()
		"jumper":   inst = jumper_scene.instantiate()
	if inst:
		inst.position = world_pos
		_attach(inst)
		inst.add_to_group("hazards")


# ─── TILE STRIP SPAWN ───────────────────────────────────────────────────

## Spawns ONE TileStrip representing a contiguous horizontal run of N tiles.
## Returns it so the caller can collect it for neighbour linking.
func _spawn_strip(start_world: Vector2, length_tiles: int, is_elevated: bool = false) -> TileStrip:
	var strip: TileStrip = tile_strip_scene.instantiate() as TileStrip
	strip.tile_size = tile_size
	strip.length_tiles = length_tiles
	strip.position = start_world - Vector2(tile_size.x * 0.5, tile_size.y * 0.5)
	if is_elevated:
		strip.no_foliage = true
	_attach(strip)
	return strip

## After all strips are placed, find horizontally-adjacent strips at the same Y and
## suppress the shared interior side outline.
func _link_strip_neighbors(strips: Array) -> void:
	var by_y: Dictionary = {}
	for strip in strips:
		if strip == null or not is_instance_valid(strip): continue
		var y_key: int = roundi(strip.position.y)
		if not by_y.has(y_key):
			by_y[y_key] = []
		by_y[y_key].append(strip)
	for y_key in by_y:
		var row: Array = by_y[y_key]
		row.sort_custom(func(a, b): return a.position.x < b.position.x)
		for i in range(row.size() - 1):
			var ls: TileStrip = row[i]
			var rs: TileStrip = row[i + 1]
			if abs((ls.position.x + ls.get_world_width()) - rs.position.x) < 4.0:
				ls.right_neighbor = true
				rs.left_neighbor  = true
				ls.refresh_visual()
				rs.refresh_visual()


func _spawn_spike(world_pos: Vector2) -> void:
	var spike = spike_scene.instantiate()
	spike.position = world_pos
	_attach(spike)
	spike.add_to_group("hazards")


# ─── TEMPLATE GATING ────────────────────────────────────────────────────

## Decide whether `tmpl` can appear given the current unlock state.
## A template is admitted if:
##   * It has no ramp glyphs.
##   * All entity glyphs (excluding 'spike' which is always allowed) refer to
##     enemies that are individually unlocked.
##   * If procgen is NOT unlocked, the template must additionally be "simple":
##     the bottom row is the only row containing '#' or 's' characters — i.e.
##     no stairs, no elevated platforms, no pit-combos.
func _template_admissible(tmpl: Dictionary) -> bool:
	var pattern: Array = tmpl["pattern"]
	# Ramps disqualify.
	for row in pattern:
		if "/" in row or "\\" in row: return false
	# Unlock gate for whole template groups (more_procgen, vertical_sections).
	var gate: String = tmpl.get("gate", "")
	if gate != "" and not Global.is_unlocked(gate):
		return false
	# Entity gating. Skip non-entity metadata keys.
	for key in tmpl.keys():
		if key in ["pattern", "gate", "type", "allow_prev", "allow_next"]: continue
		var entity_id: String = tmpl[key]
		if entity_id == "spike": continue
		if not _is_entity_allowed(entity_id): return false
	# Simple-floor check when procgen locked. Spikes ('s') are hazards on the
	# floor, not walls, so they don't disqualify a row from being "simple".
	if not Global.is_unlocked("procgen"):
		var floor_rows := 0
		for i in pattern.size():
			var row: String = pattern[i]
			if "#" in row:
				if i != pattern.size() - 1:
					return false                 # # above the bottom row → stairs / platforms
				floor_rows += 1
		if floor_rows == 0: return false
	return true

func _build_active_template_indices() -> Array:
	var out: Array = []
	for i in TEMPLATES.size():
		if _template_admissible(TEMPLATES[i]):
			out.append(i)
	if out.is_empty():
		out.append(TEMPLATE_STARTER_IDX)
	return out


# ─── SECTION-TYPE CHAINING ────────────────────────────────────────────────
# Every template has a `type`: "horizontal" (default — the flat/plateau kind we
# have always had), "vertical_up" (climbs), or "vertical_down" (descends).
# Templates may declare `allow_prev` / `allow_next` lists that gate which types
# can sit on either side of them. Recognised tokens:
#   "horizontal", "vertical_up", "vertical_down"  — concrete types
#   "any"           — matches anything
#   "any_vertical"  — matches vertical_up OR vertical_down
# A candidate section may follow the previous one only if BOTH the previous
# section's allow_next accepts the candidate's type AND the candidate's
# allow_prev accepts the previous section's type.

func _tmpl_type(tmpl: Dictionary) -> String:
	return tmpl.get("type", "horizontal")

func _tmpl_allow_prev(tmpl: Dictionary) -> Array:
	return tmpl.get("allow_prev", ["any"])

func _tmpl_allow_next(tmpl: Dictionary) -> Array:
	return tmpl.get("allow_next", ["any"])

func _type_matches(allow_list: Array, actual_type: String) -> bool:
	for a in allow_list:
		if a == "any":
			return true
		if a == "any_vertical" and (actual_type == "vertical_up" or actual_type == "vertical_down"):
			return true
		if a == actual_type:
			return true
	return false

## From the pool of admissible indices, keep only those whose type chains legally
## after a section of `prev_type` whose allow_next list is `prev_allow_next`.
## Falls back to horizontal-only (then the whole pool) so a run never dead-ends.
func _chainable_indices(pool: Array, prev_type: String, prev_allow_next: Array) -> Array:
	var out: Array = []
	for idx in pool:
		var tmpl: Dictionary = TEMPLATES[idx]
		if not _type_matches(prev_allow_next, _tmpl_type(tmpl)):
			continue
		if not _type_matches(_tmpl_allow_prev(tmpl), prev_type):
			continue
		out.append(idx)
	if out.is_empty():
		for idx in pool:
			if _tmpl_type(TEMPLATES[idx]) == "horizontal":
				out.append(idx)
	if out.is_empty():
		out = pool
	return out


# ─── MAIN GENERATION ────────────────────────────────────────────────────

## Fixed seed used before the player unlocks procgen so runs are identical.
const STARTER_SEED := 5
## Seed range so codes stay 4 chars in Global.SEED_ALPHABET (31^4 = 923521).
const SEED_MAX := 923521

func generate_level() -> void:
	# Before procgen is unlocked, force the same starter seed every run so the
	# player can learn the layout. After unlock, either use a saved seed or roll.

	if not Global.is_unlocked("procgen"):
		current_seed = STARTER_SEED
		rng.seed = STARTER_SEED
	elif current_seed == 0:
		rng.randomize()
		current_seed = (int(abs(rng.seed)) % SEED_MAX)
		rng.seed = current_seed
	else:
		rng.seed = current_seed

	# Store seed so the library and UI can reference it.
	Global.current_run_seed = current_seed
	Global.stat_bucket("seeds_visited", str(current_seed), 1)
	Global.reset_run_state()
	# Only start music if we're not already mid-gameplay track (e.g. quick retry).
	if AudioManager._music_key != "gameplay":
		AudioManager.play_music("gameplay", 1.5)

	# Adaptive sky/palette drift (no-op unless "adaptive_sky" is unlocked).
	var adaptive := Node.new()
	adaptive.set_script(preload("res://adaptive_sky.gd"))
	add_child(adaptive)

	# Palette tint — affects every canvas item in the world, so palette swaps
	# actually recolour the entire scene.
	var mod := CanvasModulate.new()
	mod.color = Global.palette_tint()
	mod.add_to_group("palette_modulate")
	add_child(mod)
	Global.palette_changed.connect(func():
		if mod:
				mod.color = Global.palette_tint()
	)

	# Persistent blood mark canvas (rendered below hazards).
	var blood_canvas = Node2D.new()
	blood_canvas.set_script(preload("res://blood_canvas.gd"))
	blood_canvas.z_index = -3
	blood_canvas.add_to_group("blood_canvas")
	add_child(blood_canvas)

	# In-game background goes in BEFORE the UI so it sits visually behind.
	add_child(bg_scene.instantiate())
	add_child(hud_scene.instantiate())
	add_child(pause_scene.instantiate())

	var ui_instance = ui_scene.instantiate()
	add_child(ui_instance)

	_active_indices = _build_active_template_indices()
	_next_x = 0
	_next_y = 0
	_block_index = 0
	_prev_type = "horizontal"
	_prev_allow_next = ["any"]
	_max_y = -99999.0

	# Block 0 is the flat safe start; the player is placed on it.
	var spawn_pos := _emit_block()
	for _i in range(PRIME_BLOCKS - 1):
		_emit_block()

	var p = player_scene.instantiate()
	spawn_pos.y -= 100
	p.position = spawn_pos
	p.set("game_over_ui", ui_instance)
	p.set("death_y_limit", _max_y + tile_size.y * 2)
	add_child(p)
	player = p
	_streaming = true


## Build the next section in the sequence and advance the cursor.
## Returns the block's player spawn point (only meaningful for block 0).
func _emit_block() -> Vector2:
	var i := _block_index
	_block_index += 1

	var tmpl_idx: int
	if i == 0:
		tmpl_idx = TEMPLATE_STARTER_IDX
	else:
		var candidates := _chainable_indices(_active_indices, _prev_type, _prev_allow_next)
		tmpl_idx = candidates[rng.randi() % candidates.size()]
	var tmpl: Dictionary = TEMPLATES[tmpl_idx]

	# Remember this section's type + hand-off rule for the next block.
	_prev_type = _tmpl_type(tmpl)
	_prev_allow_next = _tmpl_allow_next(tmpl)

	var pattern: Array = tmpl["pattern"]
	var block_w: int = pattern[0].length()
	var block_h: int = pattern.size()
	var next_x := _next_x

	# Everything this block spawns hangs off one node so culling is a single free.
	_chunk_parent = Node2D.new()
	add_child(_chunk_parent)

	# Align the block's left edge with where the previous one handed off.
	var y_offset := _next_y - _entry_row(pattern, block_h)

	var all_strips: Array = []
	var spawn_pos := Vector2.ZERO

	# ── 1) Spawn floor strips: group contiguous runs of '#' along each row.
	#         '#' creates a 3-deep strip starting at the same row.
	#         's' (spike) creates the spike sprite at that row and a
	#         1-wide strip ONE ROW LOWER, exactly matching the original
	#         per-tile spawn semantics (spike rests on top of its tile).
	for ty in range(block_h):
		var grid_y := y_offset + ty
		var row: String = pattern[ty]
		var rx := 0
		while rx < block_w:
			var ch_here: String = row[rx]
			if ch_here == '#':
				var run_start := rx
				while rx < block_w and row[rx] == '#':
					rx += 1
				var run_len := rx - run_start
				var world_start := Vector2(
					(next_x + run_start) * tile_size.x + tile_size.x * 0.5,
					grid_y * tile_size.y + tile_size.y * 0.5
				)
				# Suppress foliage on anything that isn't the block's true
				# ground row. Two triggers:
				#   1) Row directly below has empty space under the run
				#      (traditional floating platform).
				#   2) A deeper row in the block contains a '#' — meaning
				#      this strip is a stair step or upper tier, not the
				#      ground the sky sits against. Foliage tufts on those
				#      poke up into the sky and read as "grass on the sky".
				var is_elevated := false
				if ty + 1 < block_h:
					var next_row_str: String = pattern[ty + 1]
					for xx in range(run_start, rx):
						var nc: String = next_row_str[xx]
						if nc == '.' or nc == ' ' or nc == 'a':
							is_elevated = true
							break
				if not is_elevated:
					for deeper_ty in range(ty + 1, block_h):
						if pattern[deeper_ty].find('#') != -1:
							is_elevated = true
							break
				all_strips.append(_spawn_strip(world_start, run_len, is_elevated))
				var strip_bottom := world_start.y + (3 * tile_size.y)
				if strip_bottom > _max_y: _max_y = strip_bottom
			elif ch_here == 's':
				# Lift the spike a few pixels so its base sits clearly above
				# the wavy grass band instead of being clipped by it.
				var spike_world := Vector2(
					(next_x + rx) * tile_size.x + tile_size.x * 0.5,
					grid_y * tile_size.y + tile_size.y * 0.5 - 14.0
				)
				_spawn_spike(spike_world)
				var strip_world := Vector2(
					spike_world.x,
					grid_y * tile_size.y + tile_size.y * 0.5 + tile_size.y
				)
				all_strips.append(_spawn_strip(strip_world, 1))
				var sb := strip_world.y + (3 * tile_size.y)
				if sb > _max_y: _max_y = sb
				rx += 1
			else:
				rx += 1

	# ── 1b) Patterned coin placement. Coins follow arcs, lines, or clusters
	#         rather than being scattered at a flat random rate.
	if Global.is_unlocked("coins") and i > 0:
		_spawn_coins_patterned(pattern, block_w, block_h, next_x, y_offset)

	# ── 2) Spawn non-tile entities (ramps + enemies)
	for ty in range(block_h):
		var grid_y2 := y_offset + ty
		var row2: String = pattern[ty]
		for tx in range(block_w):
			var ch: String = row2[tx]
			var grid_x := next_x + tx
			var world_pos := Vector2(
				grid_x * tile_size.x + tile_size.x * 0.5,
				grid_y2 * tile_size.y + tile_size.y * 0.5
			)
			if ch == '/' or ch == '\\':
				# Ramps removed from the game — skip.
				continue
			elif ch in ['.', ' ', 'a', '#', 's']:
				pass
			elif tmpl.has(ch):
				var entity_id: String = tmpl[ch]
				var spawn_world := world_pos
				# Shooters must sit on top of the ground — snap their Y to
				# the row immediately above the nearest '#' or 's' below.
				if entity_id == "shooter":
					var floor_grid_y := -1
					for yy in range(ty + 1, block_h):
						var rrow: String = pattern[yy]
						if ("#" in rrow) or ("s" in rrow):
							floor_grid_y = y_offset + yy
							break
					if floor_grid_y != -1:
						# Snap bottom of shooter sprite to top of floor collision.
						# Shooter rect spans -64..+64 from its position, so subtract
						# one full tile height to seat it on the surface.
						spawn_world.y = floor_grid_y * tile_size.y - tile_size.y
				_spawn_entity(entity_id, spawn_world)

	if i == 0:
		spawn_pos = Vector2(next_x * tile_size.x + tile_size.x * 2.0, _next_y * tile_size.y - 55)

	# Record this block's surface heights (patching any unreachable edge column),
	# then spike any pocket the player would auto-run into and be unable to climb
	# back out of.
	all_strips.append_array(_record_floor_profile(pattern, block_w, block_h, next_x, y_offset))
	_seal_unclimbable_pockets(next_x, next_x + block_w)

	# Outline-link within the block and across the seam with the previous one.
	_link_strip_neighbors(_seam_strips + all_strips)
	_seam_strips = all_strips

	_blocks.append({
		"parent": _chunk_parent,
		"end_x": float(next_x + block_w) * tile_size.x,
	})
	_chunk_parent = null

	_next_x += block_w
	_next_y = y_offset + _exit_row(pattern, block_h, block_w)
	return spawn_pos


# ─── SECTION EDGE ALIGNMENT ─────────────────────────────────────────────
# The grid row a block hands off at. Normally this is the TOPMOST solid cell in
# the edge column, because the player walks onto the top of whatever is there.
# When the edge column is empty in every row (templates like ".######." whose
# ground row does not reach the block border) there is no such cell, and the old
# code silently used row 0 on entry / left `next_y` untouched on exit. Both
# mistakes offset the following section by the block's full height, which is
# what produced the "last platform is too high, player is stuck" sections.
# Falling back to the block's own ground row keeps the two floors level.

## Bottom-most row of the pattern containing any solid cell.
func _ground_row(pattern: Array, block_h: int) -> int:
	for y in range(block_h - 1, -1, -1):
		var row: String = pattern[y]
		if ("#" in row) or ("s" in row):
			return y
	return block_h - 1

func _entry_row(pattern: Array, block_h: int) -> int:
	for y in range(block_h):
		var ch: String = pattern[y][0]
		if ch == '#' or ch == 's':
			return y
	return _ground_row(pattern, block_h)

func _exit_row(pattern: Array, block_h: int, block_w: int) -> int:
	for y in range(block_h):
		var ch: String = pattern[y][block_w - 1]
		if ch == '#' or ch == 's':
			return y
	return _ground_row(pattern, block_h)


# ─── STUCK-POCKET SPIKES ────────────────────────────────────────────────
# The player auto-runs right and cannot backtrack, so a floor that dead-ends
# into a wall taller than a jump is a soft-lock: nothing kills them, they just
# stand there. Any such pocket gets a bed of spikes so the run ends cleanly
# instead of hanging.

## Store the topmost solid row for every column this block occupies.
##
## A column with nothing solid in it is one of two very different things:
##   • an 'a' (abyss) column — a designed pit; falling in is a death and the
##     column is deliberately left out of the profile.
##   • an EDGE column that the template's ground row simply doesn't reach
##     (patterns like ".######."). Those are accidents of the artwork, and they
##     are what broke section stitching: with no solid cell to align against,
##     the neighbouring section was placed a whole block-height out. The edge is
##     bridged with a one-tile strip at the block's own ground row so seams stay
##     flush and the player never drops into a slot between two sections.
## Returns any bridge strips created, for outline linking.
func _record_floor_profile(pattern: Array, block_w: int, block_h: int,
		next_x: int, y_offset: int) -> Array:
	var bridges: Array = []
	var ground := _ground_row(pattern, block_h)
	for tx in block_w:
		var top := -1
		for ty in range(block_h):
			var ch: String = pattern[ty][tx]
			if ch == '#' or ch == 's':
				top = ty
				break
		if top == -1:
			var is_edge: bool = (tx == 0 or tx == block_w - 1)
			var has_abyss := false
			for ay in range(block_h):
				if pattern[ay][tx] == 'a':
					has_abyss = true
					break
			if not is_edge or has_abyss:
				continue
			top = ground
			var world_start := Vector2(
				(next_x + tx) * tile_size.x + tile_size.x * 0.5,
				(y_offset + top) * tile_size.y + tile_size.y * 0.5
			)
			bridges.append(_spawn_strip(world_start, 1))
			var bb := world_start.y + (3 * tile_size.y)
			if bb > _max_y: _max_y = bb
		_floor_profile[next_x + tx] = y_offset + top
	return bridges

## Walk the freshly-placed columns (plus one of overlap with the previous block,
## so seams are covered) and spike the flat run leading into any wall higher than
## MAX_CLIMB_TILES.
func _seal_unclimbable_pockets(from_x: int, to_x: int) -> void:
	for gx in range(max(_profile_min_x, from_x - 1), to_x):
		if not _floor_profile.has(gx) or not _floor_profile.has(gx + 1):
			continue
		var here: int = _floor_profile[gx]
		var ahead: int = _floor_profile[gx + 1]
		# Smaller row = higher up. A positive climb bigger than the jump arc is
		# a wall the auto-runner can never clear.
		if here - ahead <= MAX_CLIMB_TILES:
			continue
		# Spike back along the contiguous run of ground at this same low level —
		# that flat stretch is the whole trap. Capped so a long approach doesn't
		# get carpeted; the player runs into the first few regardless.
		var bx := gx
		var placed := 0
		while bx >= _profile_min_x and placed < POCKET_SPIKE_MAX \
				and _floor_profile.get(bx, -99999) == here:
			if not _spiked_cols.has(bx):
				_spiked_cols[bx] = true
				_spike_surface(bx, here)
			bx -= 1
			placed += 1

## Drop a spike standing on top of the tile at (grid_x, floor_grid_y).
func _spike_surface(grid_x: int, floor_grid_y: int) -> void:
	_spawn_spike(Vector2(
		grid_x * tile_size.x + tile_size.x * 0.5,
		(floor_grid_y - 1) * tile_size.y + tile_size.y * 0.5 - 14.0
	))


# ─── STREAMING ──────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not _streaming: return
	if player == null or not is_instance_valid(player):
		return
	var px: float = player.global_position.x
	var built := 0
	while float(_next_x) * tile_size.x - px < GEN_AHEAD_PX and built < MAX_BLOCKS_PER_FRAME:
		_emit_block()
		built += 1
	if built > 0 and _cam != null and is_instance_valid(_cam):
		_cam.limit_bottom = int(_max_y + tile_size.y * 1.5)
	_cull_behind(px)

## Free sections the player has left behind. This is what keeps the node count —
## and player.gd's per-column scan over the `solid_tiles` group — bounded no
## matter how far the run goes.
func _cull_behind(px: float) -> void:
	while not _blocks.is_empty() and float(_blocks[0]["end_x"]) < px - CULL_BEHIND_PX:
		var b: Dictionary = _blocks.pop_front()
		var parent = b["parent"]
		if parent != null and is_instance_valid(parent):
			parent.queue_free()
	# Trim the floor profile to match, so the pocket scan can't walk into
	# columns whose geometry no longer exists.
	if _blocks.is_empty(): return
	var keep_from := int(float(_blocks[0]["end_x"]) / tile_size.x) - 64
	while _profile_min_x < keep_from:
		_floor_profile.erase(_profile_min_x)
		_profile_min_x += 1


# ─── CAMERA ─────────────────────────────────────────────────────────────

func setup_camera() -> void:
	if not player: return
	var cam = Camera2D.new()
	cam.make_current()
	cam.position = Vector2.ZERO
	player.add_child(cam)
	_cam = cam

	cam.limit_left = 0
	cam.limit_top = -10000000
	cam.limit_bottom = int(_max_y + tile_size.y * 1.5)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0

	var viewport_size = get_viewport_rect().size
	var base_zoom := 1.0
	if viewport_size.x > 0 and viewport_size.y > 0:
		var zoom_x = viewport_size.x / (tile_size.x * 14.0)
		var zoom_y = viewport_size.y / (tile_size.y * 8.0)
		base_zoom = min(zoom_x, zoom_y)
		cam.zoom = Vector2.ONE * base_zoom
	player.set("_base_zoom", base_zoom)
