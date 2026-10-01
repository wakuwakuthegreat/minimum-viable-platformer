extends CanvasLayer

## Autoloaded screen-space post-process stack.
##
## Layer layout:
##   Layer  90 (self)         — chromatic aberration only. Runs BEFORE UI (layer 95) so it
##                              never distorts UI text/buttons.
##   Layer  96 (_upper_layer) — all other passes (color_grading, vignette, crt, wobble, fog,
##                              dither, neon_glow). Runs AFTER UI so these effects apply to
##                              UI panels, text, and controls too.
##
## Each pass is a BackBufferCopy + ColorRect pair. The BBC is required in GL Compatibility
## because hint_screen_texture only samples the most recent BBC before the draw call.

var passes: Dictionary = {}      # feature_key → ColorRect
var pass_layers: Dictionary = {} # feature_key → CanvasLayer

var _chromatic_decay: float = 0.0
var _chromatic_kick: float = 0.0
const CHROMATIC_BASE := 0.006
const CHROMATIC_MAX  := 0.028

## Set each frame by player.gd when "wobble_shader" is unlocked.
var wobble_intensity: float = 0.0
var _wobble_time: float = 0.0

## Next available layer for post-UI passes (UI is typically 10-50, we start at 96).
var _next_layer_idx: int = 96

func _ready() -> void:
	# Keep this base ScreenFX node as a CanvasLayer for chromatic aberration.
	layer = 90

	# ── Chromatic aberration: layer 90 (below UI) ──────────────────────────
	_try_add_pass("chromatic_aberration", "res://shaders/chromatic.gdshader", self)

	# ── All other passes: layer 96+ (above UI) ──────────────────────────────
	# palette_shift is driven by Global.color_palette (not an unlock), see _process.
	_try_add_pass("palette_shift",  "res://shaders/palette_shift.gdshader",  null)
	_try_add_pass("color_grading",  "res://shaders/color_grading.gdshader",  null)
	_try_add_pass("fog_cover",      "res://shaders/fog_cover.gdshader",       null)
	_try_add_pass("vignette",       "res://shaders/vignette.gdshader",        null)
	if not _is_lightweight_target():
		_try_add_pass("crt_filter",    "res://shaders/crt.gdshader",          null)
		_try_add_pass("wobble_shader", "res://shaders/wobble.gdshader",       null)
		_try_add_pass("pixel_dither",  "res://shaders/pixel_dither.gdshader", null)
		_try_add_pass("neon_glow",     "res://shaders/neon_glow.gdshader",    null)
	set_process(true)

func _try_add_pass(feature_key: String, path: String, target: CanvasLayer) -> void:
	var sh: Shader = load(path) as Shader
	if sh == null:
		push_warning("ScreenFX: could not load shader '%s' — pass skipped." % path)
		return
	_add_pass(feature_key, sh, target)

func _is_lightweight_target() -> bool:
	var name := OS.get_name()
	return name in ["Web", "Android", "iOS"]

func _add_pass(feature_key: String, sh: Shader, target: CanvasLayer) -> void:
	if target == null:
		target = CanvasLayer.new()
		target.layer = _next_layer_idx
		_next_layer_idx += 1
		get_tree().root.call_deferred("add_child", target)
		pass_layers[feature_key] = target

	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	target.call_deferred("add_child", bbc)

	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.color = Color(1, 1, 1, 1)
	r.visible = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	r.material = mat
	target.call_deferred("add_child", r)
	passes[feature_key] = r

## Scenes where chromatic aberration should be suppressed (it looks bad over clean UI text).
const CHROMATIC_SUPPRESSED_SCENES := ["stats_view", "leaderboard_view"]

func _current_scene_name() -> String:
	var cs = get_tree().current_scene
	if cs == null: return ""
	# Use the file stem so it matches regardless of scene node name.
	return cs.scene_file_path.get_file().get_basename()

func _process(delta: float) -> void:
	_wobble_time += delta

	var scene_name := _current_scene_name()
	var in_level := scene_name == "leve"   # level scene is called "leve.tscn"
	var suppress_chromatic := scene_name in CHROMATIC_SUPPRESSED_SCENES

	for key in passes.keys():
		var r: ColorRect = passes[key]
		var enabled: bool = Global.is_unlocked(key) and not Global.use_primitives
		# palette_shift is gated on the active palette, not an unlock. It recolours
		# the whole scene whenever the player has picked a non-default palette.
		if key == "palette_shift":
			enabled = Global.color_palette != "default" and not Global.use_primitives
			if enabled and r.material:
				var c := Global.palette_shift_color()
				r.material.set_shader_parameter("tint_color", Vector3(c.r, c.g, c.b))
				r.material.set_shader_parameter("strength", 0.82)
				r.material.set_shader_parameter("hue_shift", Global.palette_hue() / 360.0)
		# fog_cover only makes sense during gameplay (it covers the lower screen like an abyss).
		if key == "fog_cover" and not in_level:
			enabled = false
		# Chromatic aberration looks bad over UI, so only enable it during actual gameplay.
		if key == "chromatic_aberration" and not in_level:
			enabled = false
		if r.visible != enabled:
			r.visible = enabled
			if pass_layers.has(key):
				pass_layers[key].visible = enabled

	var wobble_r: ColorRect = passes.get("wobble_shader", null)
	if wobble_r and wobble_r.material:
		wobble_r.material.set_shader_parameter("intensity", wobble_intensity)
		wobble_r.material.set_shader_parameter("time_sec", _wobble_time)

	var chromatic_amount := CHROMATIC_BASE
	if _chromatic_kick > 0.0:
		_chromatic_kick = max(0.0, _chromatic_kick - delta * _chromatic_decay)
		chromatic_amount = CHROMATIC_BASE + _chromatic_kick
	var r2: ColorRect = passes.get("chromatic_aberration", null)
	if r2 and r2.material:
		r2.material.set_shader_parameter("amount", chromatic_amount)

## Briefly bump the chromatic-aberration amount toward CHROMATIC_MAX.
func kick_chromatic(amount: float = 0.022, duration: float = 0.35) -> void:
	if duration <= 0.0: duration = 0.001
	_chromatic_kick = clamp(amount, 0.0, CHROMATIC_MAX - CHROMATIC_BASE)
	_chromatic_decay = _chromatic_kick / duration

## Trigger the glitch visual + audio sequence.
func trigger_glitch(go_silent: bool = true) -> void:
	kick_chromatic(CHROMATIC_MAX - CHROMATIC_BASE, 0.8)
	AudioManager.play_glitch_sequence(go_silent)
