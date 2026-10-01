extends Node

## Cycles Global.sky_color and Global.color_palette while a run is active,
## simulating time-of-day progression. Only runs when the "adaptive_sky"
## upgrade is bought AND the game is inside a level scene (not menus).
##
## Attached by level_generator.gd via `add_child(preload(...).new())`.

const SKY_CYCLE := ["dawn", "default", "sunset", "night", "overcast"]
const PAL_CYCLE := ["default", "warm", "cool", "night"]
const PHASE_LEN := 22.0  # seconds per phase

var _saved_sky: String = ""
var _saved_palette: String = ""
var _elapsed: float = 0.0
var _last_sky_idx: int = -1
var _last_pal_idx: int = -1

func _ready() -> void:
	_saved_sky = Global.sky_color
	_saved_palette = Global.color_palette
	set_process(true)

func _process(delta: float) -> void:
	if not Global.is_unlocked("adaptive_sky"): return
	_elapsed += delta
	var t := int(_elapsed / PHASE_LEN)
	var sky_idx := t % SKY_CYCLE.size()
	var pal_idx := (t / SKY_CYCLE.size()) % PAL_CYCLE.size()
	if sky_idx != _last_sky_idx:
		Global.sky_color = SKY_CYCLE[sky_idx]
		_last_sky_idx = sky_idx
	# Only drive the palette when the player has NOT chosen one themselves —
	# otherwise the cycle (which starts on "default" at t=0) would wipe out the
	# palette the player picked, making it look like palettes don't work in-game.
	if _saved_palette == "default":
		if pal_idx != _last_pal_idx:
			Global.color_palette = PAL_CYCLE[pal_idx]
			_last_pal_idx = pal_idx

func _exit_tree() -> void:
	# Restore player-chosen values when the level unloads so menus look normal.
	Global.sky_color = _saved_sky
	Global.color_palette = _saved_palette
