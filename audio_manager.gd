extends Node

## Central audio autoload.  Everything goes through here.
## Feature gates: "sfx" = sound effects, "music" = background music,
##               "wind_effect" = wind visual + audio at combo > 3.

# ─── SFX POOL ───────────────────────────────────────────────────────────────
const POOL_SIZE := 12
var _pool: Array[AudioStreamPlayer] = []

# Dedicated looping player for wind (kept alive across combo spans).
var _wind_player: AudioStreamPlayer = null
var _wind_active: bool = false
var _wind_tween: Tween = null

# Music player (cross-fades).
var _music_player: AudioStreamPlayer = null
var _music_key: String = ""
var _music_tween: Tween = null

# ─── ASSET TABLES ────────────────────────────────────────────────────────────
# Use load() so paths with spaces compile fine.
var SFX: Dictionary = {}
var MUSIC: Dictionary = {}

func _ready() -> void:
	_build_sfx_table()
	_build_music_table()

	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

	_wind_player = AudioStreamPlayer.new()
	add_child(_wind_player)
	var wind_stream = SFX.get("wind")
	if wind_stream:
		_wind_player.stream = wind_stream
	_wind_player.volume_db = -80.0
	_wind_player.finished.connect(_on_wind_finished)

	_music_player = AudioStreamPlayer.new()
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)

func _build_sfx_table() -> void:
	SFX = {
		"footstep": [
			load("res://assets/sounds/sfx_movement_footsteps1a.wav"),
			load("res://assets/sounds/sfx_movement_footsteps1b.wav"),
		],
		"jump_normal":   load("res://assets/sounds/BounceYoFrankie.ogg"),
		"jump_spring":   load("res://assets/sounds/spring_jump_qubodup-cfork-ccby3-jump.ogg"),
		"hurt_player":   load("res://assets/sounds/Socapex - hurt.wav"),
		"monster_hurt":  load("res://assets/sounds/Socapex - Monster_Hurt.wav"),
		"new_hits": [
			load("res://assets/sounds/Socapex - new_hits_1.wav"),
			load("res://assets/sounds/Socapex - new_hits_5.wav"),
		],
		"grunt": [
			load("res://assets/sounds/male_grunt_2 (1).wav"),
			load("res://assets/sounds/male_grunt_2 (2).wav"),
		],
		"smallsword": [
			load("res://assets/sounds/Socapex - Swordsmall.wav"),
			load("res://assets/sounds/Socapex - Swordsmall_1.wav"),
			load("res://assets/sounds/Socapex - Swordsmall_2.wav"),
			load("res://assets/sounds/Socapex - Swordsmall_3.wav"),
		],
		"explosion":  load("res://assets/sounds/missile_explosion.ogg"),
		"engine":     load("res://assets/sounds/Engine.wav"),
		"glitch_sfx": load("res://assets/sounds/glitch_sound.wav"),
		"tick":       load("res://assets/sounds/tick_004.ogg"),
		"wind":       load("res://assets/sounds/wind.ogg"),
		"ui_click":   load("res://assets/sounds/ui/bong_001.ogg"),
		"ui_confirm": load("res://assets/sounds/ui/confirmation_001.ogg"),
		"ui_drop": [
			load("res://assets/sounds/ui/drop_001.ogg"),
			load("res://assets/sounds/ui/drop_002.ogg"),
			load("res://assets/sounds/ui/drop_003.ogg"),
		],
		"ui_glass":   load("res://assets/sounds/ui/glass_001.ogg"),
		"ui_buy":     load("res://assets/sounds/ui/buy_glass_004.ogg"),
		"switch_on":  load("res://assets/sounds/ui/switch_on.ogg"),
		"switch_off": load("res://assets/sounds/ui/switch_off.ogg"),
		"gem_gather": load("res://assets/sounds/gem-gather-stereo-reverb.wav"),
	}

func _build_music_table() -> void:
	MUSIC = {
		"main_menu": load("res://assets/music/Main Menu - cauliflower.ogg"),
		"menu_alt":  load("res://assets/music/Menu Alt - Of Far Different Nature - HEY (CC-BY).ogg"),
		"gameplay": [
			load("res://assets/music/Gameplay - Breathe.mp3"),
			load("res://assets/music/Gameplay - Of Far Different Nature - Ganxta (CC-BY).ogg"),
			load("res://assets/music/Gameplay - Of Far Different Nature - Nature Loop (CC-BY).ogg"),
			load("res://assets/music/Gameplay - shortcuts.ogg"),
		],
		"shop":  load("res://assets/music/Shop Loop - Of Far Different Nature - Ethnic Beat (CC-BY).ogg"),
		"glitch":load("res://assets/music/glitch_song.mp3"),
	}

# ─── VOLUME HELPERS ──────────────────────────────────────────────────────────

func _sfx_db() -> float:
	return linear_to_db(max(0.001, float(Global.settings_cfg.get("sfx_volume", 0.8))))

func _music_db() -> float:
	return linear_to_db(max(0.001, float(Global.settings_cfg.get("master_volume", 0.8)))) - 9.0

## Call from settings sliders when volume changes.
func apply_volumes() -> void:
	if _music_player.playing:
		_music_player.volume_db = _music_db()

# ─── SFX PLAYBACK ────────────────────────────────────────────────────────────

func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[0]  # steal oldest

## Play a one-shot SFX. vol_offset is dB added on top of sfx_volume.
## pitch_var is the ± random pitch range.
func play(key: String, vol_offset: float = 0.0, pitch_var: float = 0.06) -> void:
	if not Global.is_unlocked("sfx"): return
	var entry = SFX.get(key)
	if entry == null: return
	var stream: AudioStream
	if entry is Array:
		stream = entry[randi() % entry.size()]
	else:
		stream = entry
	if stream == null: return
	var p := _free_player()
	p.stream = stream
	p.volume_db = _sfx_db() + vol_offset
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()

## Returns true when world_pos is within the current viewport's visible rect.
func is_on_screen(world_pos: Vector2) -> bool:
	var vp := get_viewport()
	if not vp: return true
	var sp: Vector2 = vp.get_canvas_transform() * world_pos
	return vp.get_visible_rect().has_point(sp)

## Play SFX with reduced volume when world_pos is off-screen.
func play_at(key: String, world_pos: Vector2, vol_offset: float = 0.0, off_screen_penalty: float = -14.0) -> void:
	if not Global.is_unlocked("sfx"): return
	var extra: float = 0.0
	var vp := get_viewport()
	if vp:
		var sp: Vector2 = vp.get_canvas_transform() * world_pos
		if not vp.get_visible_rect().has_point(sp):
			extra = off_screen_penalty
	play(key, vol_offset + extra)

# ─── MUSIC ───────────────────────────────────────────────────────────────────

## Fade in music for the given key. No-op if same track is already playing.
func play_music(key: String, fade: float = 1.2) -> void:
	if not Global.is_unlocked("music"):
		_fade_out(fade)
		return
	var entry = MUSIC.get(key)
	if entry == null:
		return
	var stream: AudioStream
	if entry is Array:
		stream = entry[randi() % entry.size()]
	else:
		stream = entry
	if stream == null: return
	if _music_player.stream == stream and _music_player.playing:
		return  # already playing this track
	_music_key = key
	if _music_tween: _music_tween.kill()
	if _music_player.playing:
		# Cross-fade: fade out current, then start new.
		_music_tween = create_tween()
		_music_tween.tween_property(_music_player, "volume_db", -80.0, fade * 0.45)
		_music_tween.tween_callback(func():
			_music_player.stream = stream
			_music_player.volume_db = -80.0
			_music_player.play()
			var tw2 := create_tween()
			tw2.tween_property(_music_player, "volume_db", _music_db(), fade * 0.55)
		)
	else:
		_music_player.stream = stream
		_music_player.volume_db = -80.0
		_music_player.play()
		_music_tween = create_tween()
		_music_tween.tween_property(_music_player, "volume_db", _music_db(), fade)

func stop_music(fade: float = 1.2) -> void:
	_fade_out(fade)
	_music_key = ""

func _fade_out(fade: float) -> void:
	if not _music_player.playing: return
	if _music_tween: _music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -80.0, fade)
	_music_tween.tween_callback(_music_player.stop)

func _on_music_finished() -> void:
	# Loop: replay the same key with a gentle fade-in.
	if _music_key != "":
		play_music(_music_key, 0.4)

func _on_wind_finished() -> void:
	if _wind_active and _wind_player.stream != null:
		_wind_player.play()

# ─── GLITCH SEQUENCE ────────────────────────────────────────────────────────

## Trigger glitch SFX + glitch music, then optional silence.
func play_glitch_sequence(go_silent: bool = true) -> void:
	play("glitch_sfx", 0.0, 0.02)
	if not Global.is_unlocked("music"): return
	var glitch_stream = MUSIC.get("glitch")
	if glitch_stream == null: return
	_music_key = ""
	if _music_tween: _music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -80.0, 0.25)
	_music_tween.tween_callback(func():
		_music_player.stream = glitch_stream
		_music_player.volume_db = _music_db()
		_music_player.play()
		if go_silent:
			_music_player.finished.connect(func():
				_music_key = ""
			, CONNECT_ONE_SHOT)
		else:
			_music_key = "glitch"
	)

# ─── WIND LOOP ───────────────────────────────────────────────────────────────

## Enable or disable the looping wind audio. Fades in/out smoothly.
func set_wind_audio(active: bool) -> void:
	if not Global.is_unlocked("wind_effect"): return
	if _wind_active == active: return
	_wind_active = active
	if _wind_tween: _wind_tween.kill()
	_wind_tween = create_tween()
	if active:
		var ws = SFX.get("wind")
		if ws == null: return
		if not _wind_player.playing:
			_wind_player.stream = ws
			_wind_player.volume_db = -80.0
			_wind_player.play()
		_wind_tween.tween_property(_wind_player, "volume_db", _sfx_db() - 4.0, 1.2)
	else:
		_wind_tween.tween_property(_wind_player, "volume_db", -80.0, 1.8)
		_wind_tween.tween_callback(_wind_player.stop)

# ─── UI HELPER ────────────────────────────────────────────────────────────────

## Recursively connect all Button nodes under `root` to play "ui_click" on press.
## Call this in each menu's _ready() with UITheme.apply_current or after building UI.
func connect_ui_clicks(root: Node) -> void:
	if not Global.is_unlocked("sfx"): return
	for child in root.get_children():
		if child is Button:
			if not child.pressed.is_connected(_on_ui_button_pressed):
				child.pressed.connect(_on_ui_button_pressed)
		connect_ui_clicks(child)

func _on_ui_button_pressed() -> void:
	play("ui_click", -2.0, 0.04)
