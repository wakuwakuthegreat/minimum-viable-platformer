extends Node

@export_multiline var README: String = "IMPORTANT: This script automatically initializes the Input Map configuration for 'left', 'right', 'jump', 'dash', 'up', and 'down' at boot. Physical keys are assigned programmatically."

# ─── CAMERA ZOOM SETTINGS ──────────────────────────────────────────────────
## 1 = Zoom out when a hazard is further than camera_hazard_distance from the player
## 2 = Zoom out when fewer than camera_tile_threshold solid tiles are visible on screen
@export_enum("Hazard Distance:1", "Tile Count:2") var camera_zoom_mode: int = 2

@export var debugText: bool = true
## When true, ALL entities ignore their unlock flags and draw primitives.
## Default false — visual unlocks then control what's drawn.
@export var use_primitives: bool = false


## How much to multiply the base zoom by when zoomed out (< 1.0 = further out)
@export var camera_zoom_out_factor: float = 0.62

## [Mode 1] If a hazard is beyond this many pixels ahead, zoom out
@export var camera_hazard_distance: float = 900.0

## [Mode 2] If fewer than this many solid tiles are visible, zoom out
@export var camera_tile_threshold: int = 12

## Tween duration for zoom transitions in seconds
@export var camera_zoom_tween_duration: float = 0.55

# ─── DEBUG ──────────────────────────────────────────────────────────────
## Show debug overlay (FPS, memory, velocity, zoom, momentum, stun)
@export var debug_text: bool = false

## Persistent dictionary of debug toggles, easy to extend with new features.
@export var debug_toggles: Dictionary = {
	"auto_restart": false,
	"keep_seed": false,
	"show_collisions": false,
	"show_overlay": false,
	"unlock_all": false,
}

var player : Node2D;

# ─── META-PROGRESSION ──────────────────────────────────────────────────
## Currency the player earns from running.
var tokens: int = 0

## Dictionary of unlocked feature keys. e.g. { "ui": true, "juice_squash": true }
var unlocked: Dictionary = {}

## Per-feature enabled overrides — false means the skill was bought but is turned off.
## Defaults to true (enabled) for all keys not present.
var feature_overrides: Dictionary = {}

## Features on loan for a single run, earned by watching a rewarded ad in the
## shop. Read by is_unlocked() exactly like a real purchase, then cleared when
## the run ends. Persisted so a crash between the ad and the run doesn't eat
## something the player already paid attention for.
var trial_unlocks: Dictionary = {}

## Last-known RevenueCat entitlement state, mirrored out of IAP so a cold start
## with no network still honours a purchase. IAP owns this — never write it from
## anywhere else.
var iap_entitlements: Dictionary = {}

## True the first time the player has died at least once.
var first_death_done: bool = false

## True once the intro tutorial has been shown.
var tutorial_seen: bool = false

## StoryDB scene ids already played, so a once-only cut never repeats.
var story_seen: Dictionary = {}

## True when the player backed out of gameplay via the OS-quit shortcut
## before the menu was even unlocked (pause_menu.gd's very-early-state
## branch). Read by StoryDB's "early_quit_pending" condition to greet them
## with one narrator line on their next run, then cleared.
var early_quit_before_unlock: bool = false

## Position in the forced first-run guide. See onboarding.gd for the values.
var onboard_step: String = ""

## True once a death has armed the second guide (the polish pass that walks the
## player to Squash & Stretch / Player Sprite / Menu Polish). Set by
## Onboarding.arm_phase2() and cleared once the whole chain is owned, so the
## guide survives the level → menu → shop scene changes it has to cross.
var onboard2_armed: bool = false

## Deaths since the player last opened the shop, and whether that streak has
## armed the enemy guide (Onboarding phase 3). Reset / cleared like phase 2.
var runs_since_shop: int = 0
var onboard3_armed: bool = false

## Unix time this save was last written, and how many real days passed between
## the previous session and this one. StoryDB's days_away_at_least reads the gap.
var last_played_unix: int = 0
var session_gap_days: float = 0.0

## Best distance ever (in tile-units).
var best_distance: int = 0

var _circle_tex: GradientTexture2D = null

func get_circle_texture() -> Texture2D:
	if not _circle_tex:
		# Solid centre → transparent edge, with a ~1 px anti-aliased rim. Set
		# the arrays wholesale: Gradient refuses to drop to zero points, so the
		# old remove_point() dance logged an error and left a stray stop behind.
		var grad = Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.46, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1),
			Color(1, 1, 1, 0), Color(1, 1, 1, 0)])
		_circle_tex = GradientTexture2D.new()
		_circle_tex.gradient = grad
		_circle_tex.fill = GradientTexture2D.FILL_RADIAL
		_circle_tex.fill_from = Vector2(0.5, 0.5)
		_circle_tex.fill_to = Vector2(1, 0.5)
		# 64 px so particles are drawn at or below native size. The old 16 px
		# dot was scaled up 3–6× and came out as a soft blur. Every
		# scale_amount_* in the game is tuned against this size: diameter in
		# pixels = 64 × scale.
		_circle_tex.width = 64
		_circle_tex.height = 64
	return _circle_tex

## Score for the current run — accumulates tokens*mult + stomp bonuses.
var current_run_score: int = 0

## Highest combo achieved in the current run.
var current_run_highest_combo: int = 0

## Best score ever recorded, across every level.
var best_score_ever: int = 0

## Best score for the currently-playing seed (if any).
var current_seed_best_score: int = 0

## Tracks last awarded distance so we don't double-award mid-run.
var last_run_distance: int = 0

## Tokens accumulated in the current live run (resets on new run). Shown in HUD.
var run_tokens_gained: int = 0

## Human-readable cause of the last death, shown on the game-over screen.
var last_death_cause: String = ""

## Set true when a run was started as the Daily Level.
var is_daily_run: bool = false

## Seed of the currently running (or most recently run) level.
var current_run_seed: int = 0

## Saved level library entries. Each entry: {seed, distance, favorite}.
var level_library: Array = []

## Active colour palette key. Options: "default", "warm", "cool", "night", "neon"
var color_palette: String = "default":
	set(v):
		color_palette = v
		emit_signal("palette_changed")

signal palette_changed()
signal sky_changed()

## Active sky colour key. Options: "default", "sunset", "night", "dawn", "overcast"
var sky_color: String = "default":
	set(v):
		sky_color = v
		emit_signal("sky_changed")

## Returns a canvas-modulate tint colour representing the active palette.
func palette_tint() -> Color:
	match color_palette:
		"warm":  return Color(1.15, 0.95, 0.80)
		"cool":  return Color(0.80, 0.95, 1.15)
		"night": return Color(0.55, 0.60, 0.85)
		"neon":  return Color(1.20, 0.70, 1.20)
		_:       return Color.WHITE

## Hue rotation (in degrees, 0–360) applied full-screen by the palette_shift
## ScreenFX pass. "default" is 0 (no shift). Single source of truth for the
## palette recolour — screen_fx.gd reads this each frame.
func palette_hue() -> float:
	match color_palette:
		"warm":  return 25.0
		"cool":  return 180.0
		"night": return 210.0
		"neon":  return 290.0
		_:       return 0.0

## Vivid base colour the full-screen palette_shift pass maps every pixel toward.
## screen_fx.gd reads this each frame so grey/white pixels recolour too.
func palette_shift_color() -> Color:
	match color_palette:
		"warm":  return Color(1.00, 0.55, 0.15)
		"cool":  return Color(0.25, 0.60, 1.00)
		"night": return Color(0.35, 0.40, 0.90)
		"neon":  return Color(1.00, 0.20, 1.00)
		_:       return Color(1.0, 1.0, 1.0)

## Persisted settings (audio, theme, etc.)
var settings_cfg: Dictionary = {
	"master_volume": 0.8,
	"sfx_volume": 0.8,
	"theme": "polished",
	"blood_trail": true,
	"font_choice": "default",
	"fast_mode": false,
	"show_collisions": false,
}

## Persisted lifetime stats — displayed in the Stats menu.
var stats: Dictionary = {
	"playtime_sec": 0.0,
	"jumps": 0,
	"longest_run_m": 0,
	"highest_jump_px": 0,
	"longest_combo": 0,
	"deaths": 0,
	"deaths_by_cause": {},
	"bullets_fired": 0,
	"total_distance_m": 0,
	"total_points_earned": 0,
	"total_points_spent": 0,
	"upgrades_bought": 0,
	"sessions": 0,
	"seeds_visited": {},
	"days_played": {},
	"daily_completed": 0,
	"enemies_stomped": 0,
}

## Alphabet used for short seed codes. Excludes ambiguous chars (0/O, 1/I/L).
const SEED_ALPHABET := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const SEED_CODE_LEN := 4

## 4-char alphanumeric code from a seed. Deterministic.
static func seed_to_code(seed_val: int) -> String:
	var base := SEED_ALPHABET.length()
	var v := int(abs(seed_val))
	var out := ""
	for i in SEED_CODE_LEN:
		out = SEED_ALPHABET[v % base] + out
		v = v / base
	return out

## Inverse. Returns 0 if code is invalid.
static func code_to_seed(code: String) -> int:
	var s := code.strip_edges().to_upper()
	if s.length() != SEED_CODE_LEN: return 0
	var base := SEED_ALPHABET.length()
	var v := 0
	for i in s.length():
		var ch := s[i]
		var idx := SEED_ALPHABET.find(ch)
		if idx < 0: return 0
		v = v * base + idx
	return v

const META_SAVE_PATH := "user://meta.dat"
const TOKEN_PER_TILES := 25       # 1 token per 25 tiles ran
## End-of-run bonus granted by the Publisher Deal IAP. Applied alongside the
## fast-mode and enemy-tier bonuses in on_player_death() rather than inside
## add_tokens_flat(), so a coin is still worth exactly the 1 its popup claims.
const PUBLISHER_TOKEN_BONUS := 0.50
const FIRST_DEATH_BONUS := 1      # free token on first death so player can buy UI


func _ready() -> void:
	print("[Global] _ready() called — initialising input map")
	_initialize_input_map()
	load_state()
	# Restore collision-debug state so it persists across scenes.
	var _col_on := bool(settings_cfg.get("show_collisions", false))
	get_tree().debug_collisions_hint = false#_col_on
	debug_toggles["show_collisions"] = false#_col_on
	set_process(true)
	print("[Global] _ready() complete | tokens=", tokens, " unlocked=", unlocked)

var _playtime_save_accum: float = 0.0
## Coalesced-save state. See save_state_deferred().
var _save_dirty: bool = false
var _save_dirty_accum: float = 0.0
const SAVE_DEBOUNCE := 0.6

func _process(delta: float) -> void:
	stats["playtime_sec"] = float(stats.get("playtime_sec", 0.0)) + delta
	_playtime_save_accum += delta
	if _playtime_save_accum > 30.0:
		_playtime_save_accum = 0.0
		save_state()
	if _save_dirty:
		_save_dirty_accum += delta
		if _save_dirty_accum >= SAVE_DEBOUNCE:
			save_state()

func _notification(what: int) -> void:
	# Never let a debounced save die with the app.
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_EXIT_TREE:
			flush_save()


## ─── PERSISTENCE ────────────────────────────────────────────────────────

## Mark the save dirty instead of writing now. A full store_var costs a
## disk round-trip, and coin pickups can fire many times per second — writing
## per pickup is what made a coin-heavy run stutter. The pending write lands
## within SAVE_DEBOUNCE, on app pause/close, or on any explicit save_state().
func save_state_deferred() -> void:
	_save_dirty = true

## Write immediately if anything is pending. Cheap when nothing is dirty.
func flush_save() -> void:
	if _save_dirty:
		save_state()

func save_state() -> void:
	_save_dirty = false
	_save_dirty_accum = 0.0
	var f = FileAccess.open(META_SAVE_PATH, FileAccess.WRITE)
	if not f: return
	var blob = {
		"tokens": tokens,
		"unlocked": unlocked,
		"feature_overrides": feature_overrides,
		"trial_unlocks": trial_unlocks,
		"iap_entitlements": iap_entitlements,
		"first_death_done": first_death_done,
		"tutorial_seen": tutorial_seen,
		"best_distance": best_distance,
		"best_score_ever": best_score_ever,
		"settings_cfg": settings_cfg,
		"level_library": level_library,
		"color_palette": color_palette,
		"sky_color": sky_color,
		"stats": stats,
		"story_seen": story_seen,
		"early_quit_before_unlock": early_quit_before_unlock,
		"onboard_step": onboard_step,
		"onboard2_armed": onboard2_armed,
		"onboard3_armed": onboard3_armed,
		"runs_since_shop": runs_since_shop,
		"last_played_unix": int(Time.get_unix_time_from_system()),
	}
	f.store_var(blob)
	f.close()

func load_state() -> void:
	if not FileAccess.file_exists(META_SAVE_PATH): return
	var f = FileAccess.open(META_SAVE_PATH, FileAccess.READ)
	if not f: return
	var blob = f.get_var()
	f.close()
	if typeof(blob) != TYPE_DICTIONARY: return
	tokens = int(blob.get("tokens", 0))
	unlocked = blob.get("unlocked", {})
	feature_overrides = blob.get("feature_overrides", {})
	trial_unlocks = blob.get("trial_unlocks", {})
	iap_entitlements = blob.get("iap_entitlements", {})
	first_death_done = bool(blob.get("first_death_done", false))
	tutorial_seen = bool(blob.get("tutorial_seen", false))
	best_distance = int(blob.get("best_distance", 0))
	best_score_ever = int(blob.get("best_score_ever", 0))
	for k in blob.get("settings_cfg", {}).keys():
		settings_cfg[k] = blob["settings_cfg"][k]
	level_library = blob.get("level_library", [])
	color_palette = String(blob.get("color_palette", "default"))
	sky_color = String(blob.get("sky_color", "default"))
	var stored_stats = blob.get("stats", {})
	if typeof(stored_stats) == TYPE_DICTIONARY:
		for k in stored_stats.keys():
			stats[k] = stored_stats[k]
	story_seen = blob.get("story_seen", {})
	early_quit_before_unlock = bool(blob.get("early_quit_before_unlock", false))
	onboard_step = String(blob.get("onboard_step", ""))
	onboard2_armed = bool(blob.get("onboard2_armed", false))
	onboard3_armed = bool(blob.get("onboard3_armed", false))
	runs_since_shop = int(blob.get("runs_since_shop", 0))
	# Gap since the previous session, measured before we stamp "now".
	var now := int(Time.get_unix_time_from_system())
	var prev := int(blob.get("last_played_unix", 0))
	if prev > 0 and now > prev:
		session_gap_days = float(now - prev) / 86400.0
	last_played_unix = now
	stats["sessions"] = int(stats.get("sessions", 0)) + 1
	_mark_today_played()

func _mark_today_played() -> void:
	var d: Dictionary = Time.get_date_dict_from_system()
	var key := "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]
	var days: Dictionary = stats.get("days_played", {})
	days[key] = true
	stats["days_played"] = days

## Record a stat delta. Use for counters. Persists on save_state.
func stat_add(key: String, delta = 1) -> void:
	stats[key] = (stats.get(key, 0) if typeof(stats.get(key, 0)) == typeof(delta) else 0) + delta

## Track high-water marks (e.g. longest run, highest jump).
func stat_max(key: String, value) -> void:
	if value > stats.get(key, 0):
		stats[key] = value

## Bucketed counter (e.g. deaths_by_cause[cause] += 1).
func stat_bucket(bucket_key: String, entry_key: String, delta: int = 1) -> void:
	var b: Dictionary = stats.get(bucket_key, {})
	b[entry_key] = int(b.get(entry_key, 0)) + delta
	stats[bucket_key] = b


## ─── FEATURE QUERIES ───────────────────────────────────────────────────

func is_tutorial_run() -> bool:
	return not tutorial_seen

func is_unlocked(feature_key: String) -> bool:
	var owned: bool = debug_toggles.get("unlock_all", false) 			or bool(unlocked.get(feature_key, false)) 			or bool(trial_unlocks.get(feature_key, false))
	if is_tutorial_run():
		var fake_unlocks := ["hud", "pause_menu", "juice_squash", "hit_flash", "impact_freeze", "motion_trail", "footstep_dust", "tear_effects", "blood_splats", "blood_marks", "camera_shake", "dynamic_zoom", "vignette",  "color_grading", "crt_filter", "wobble_shader", "double_jump", "wall_jump", "drawn_floors", "foliage", "particles", "player_sprite", "sprite_animations", "outline", "parallax", "clouds", "sky_color", "enemies_basic", "enemy_sprites", "enemies_more", "enemies_advanced", "smashers", "leaderboard", "fast_mode", "font_select", "sprite_explosion",  "adaptive_sky", "combo_system", "combo_bounce", "fog_cover", "near_miss_slowmo", "sfx", "music", "wind_effect"]
		# ["hud", "player_sprite", "sprite_animations", "particles", "juice_squash", "double_jump", "sprint", "enemies_basic", "enemies_more", "enemies_advanced", "procgen", "color_grading", "vignette", "fog_cover", "dynamic_zoom", "camera_shake"]
		if feature_key in fake_unlocks:
			owned = true

	if not owned:
		return false
	# Respect per-feature toggle (default true = enabled).
	return bool(feature_overrides.get(feature_key, true))

## Graphics-gate helper used by every sprite-loading entity.
## Returns true when "use sprite art" is wanted for the given unlock key.
func gfx(feature_key: String) -> bool:
	if use_primitives: return false
	return is_unlocked(feature_key)

## True when this feature is only active because of a rewarded-ad trial — the
## shop uses it to keep showing the real price instead of claiming OWNED.
func is_trial_unlock(feature_key: String) -> bool:
	return bool(trial_unlocks.get(feature_key, false)) and not bool(unlocked.get(feature_key, false))

## Lend a feature for one run. Cleared by on_player_death().
func grant_trial_unlock(feature_key: String) -> void:
	if bool(unlocked.get(feature_key, false)): return
	trial_unlocks[feature_key] = true
	stat_add("trial_unlocks_watched", 1)
	save_state()

func clear_trial_unlocks() -> void:
	if trial_unlocks.is_empty(): return
	trial_unlocks = {}
	save_state()

## Does the player own the Publisher Deal? Asked through IAP so the entitlement
## has one owner, with the persisted mirror as the offline fallback.
func owns_publisher_deal() -> bool:
	var iap = get_node_or_null("/root/IAP")
	if iap and iap.has_method("owns_publisher_deal"):
		return iap.owns_publisher_deal()
	return bool(iap_entitlements.get("publisher_deal", false))

func grant(feature_key: String) -> void:
	if not unlocked.get(feature_key, false):
		stat_add("upgrades_bought", 1)
	unlocked[feature_key] = true
	# Auto-enable when first purchased.
	feature_overrides[feature_key] = true
	save_state()

## Spend N tokens. Returns true if successful.
func spend(n: int) -> bool:
	if tokens < n: return false
	tokens -= n
	stat_add("total_points_spent", n)
	save_state()
	return true

func add_tokens(n: int) -> void:
	if n <= 0: return
	# ComboSystem scales token earning while a combo is live.
	var mult := 1
	var cs = get_node_or_null("/root/ComboSystem")
	if cs and cs.has_method("token_multiplier"):
		mult = int(cs.token_multiplier())
	# Enemy-unlock bonus: each tier of enemy added to the game rewards +20%
	# token gain as a thank-you for making the run harder. Tiers stack, so
	# owning all four gives +80% on top of the base rate.
	var enemy_bonus: float = 1.0
	for ekey in ["enemies_basic", "enemies_more", "enemies_advanced", "smashers"]:
		if is_unlocked(ekey):
			enemy_bonus += 0.20
	var earned := int(round(n * mult * enemy_bonus))
	tokens += earned
	run_tokens_gained += earned
	stat_add("total_points_earned", earned)
	add_run_score(earned)
	save_state_deferred()

## Credit exactly `n` tokens with no combo/enemy multipliers applied. Coins use
## this so one coin is always worth exactly its face value (1), keeping the
## credited amount in sync with the +1 TokenPop popup.
func add_tokens_flat(n: int) -> void:
	if n <= 0: return
	tokens += n
	run_tokens_gained += n
	stat_add("total_points_earned", n)
	add_run_score(n)
	# Debounced — a run can collect dozens of coins a second and each one used
	# to force a full save blob to disk.
	save_state_deferred()

## Credit tokens earned by watching a rewarded ad. Deliberately does NOT touch
## current_run_score: the run is already over and its score has been compared
## against best_score_ever, so inflating it afterwards would put a number on the
## board that no run actually scored.
func grant_ad_bonus_tokens(n: int) -> void:
	if n <= 0: return
	tokens += n
	stat_add("total_points_earned", n)
	stat_add("ad_bonus_tokens", n)
	save_state()

## Adds to the current-run score. Called by ComboSystem when tokens are earned
## and by stomp-bonus paths. Does not persist until run-end.
func add_run_score(n: int) -> void:
	if n <= 0: return
	current_run_score += n

## Look up the stored best score for a given seed from the level library.
func best_score_for_seed(seed_val: int) -> int:
	for entry in level_library:
		if int(entry.get("seed", 0)) == seed_val:
			return int(entry.get("best_score", 0))
	return 0

## Reset per-run counters. Call at level start.
func reset_run_state() -> void:
	current_run_score = 0
	current_run_highest_combo = 0
	run_tokens_gained = 0
	current_seed_best_score = best_score_for_seed(current_run_seed)
	var cs = get_node_or_null("/root/ComboSystem")
	if cs and cs.has_method("reset"):
		cs.reset()

## Convenience for clearing all progress (used in settings reset).
func reset_progress() -> void:
	tokens = 0
	unlocked = {}
	feature_overrides = {}
	trial_unlocks = {}
	# iap_entitlements is deliberately NOT cleared — resetting your own progress
	# must never revoke a real purchase.
	first_death_done = false
	tutorial_seen = false
	story_seen = {}
	early_quit_before_unlock = false
	onboard_step = ""
	onboard2_armed = false
	onboard3_armed = false
	runs_since_shop = 0
	best_distance = 0
	level_library = []
	color_palette = "default"
	sky_color = "default"
	# The font pick belongs to the Font Select upgrade being reset above.
	settings_cfg["font_choice"] = "default"
	save_state()

## Enable or disable a purchased feature without losing it.
func set_feature_override(feature_key: String, enabled: bool) -> void:
	feature_overrides[feature_key] = enabled
	save_state()


## ─── LEVEL LIBRARY ─────────────────────────────────────────────────────

func add_to_library(seed_val: int, distance_m: int) -> void:
	if not is_unlocked("level_library"): return
	if seed_val == 0: return
	for entry in level_library:
		if entry.get("seed", 0) == seed_val:
			if distance_m > entry.get("distance", 0):
				entry["distance"] = distance_m
			save_state()
			return
	level_library.append({
		"seed": seed_val,
		"distance": distance_m,
		"favorite": false,
	})
	# Evict oldest non-favourite entries if over cap.
	var non_fav: Array = []
	for e in level_library:
		if not e.get("favorite", false):
			non_fav.append(e)
	while non_fav.size() > 100:
		var oldest = non_fav.pop_front()
		level_library.erase(oldest)
	save_state()


## ─── DEATH BOOKKEEPING ─────────────────────────────────────────────────

## Called by player.die().
## Returns the number of tokens awarded this death (for UI display).
func on_player_death(distance_tiles: int) -> int:
	var cs = get_node_or_null("/root/ComboSystem")
	if cs and cs.has_method("reset"):
		cs.reset()
	var awarded := 0
	if distance_tiles > 0:
		awarded = max(1, distance_tiles / TOKEN_PER_TILES)
	if not first_death_done:
		first_death_done = true
		awarded += FIRST_DEATH_BONUS
	# Fast Mode pays a 50% bounty on top of the base reward.
	if is_unlocked("fast_mode") and bool(settings_cfg.get("fast_mode", false)):
		awarded = int(round(awarded * 1.5))
	# Enemy-unlock bonus (mirrors add_tokens logic): each tier adds +20%.
	var enemy_bonus: float = 1.0
	for ekey in ["enemies_basic", "enemies_more", "enemies_advanced", "smashers"]:
		if is_unlocked(ekey):
			enemy_bonus += 0.20
	awarded = int(round(awarded * enemy_bonus))
	# Publisher Deal (IAP): permanent end-of-run bounty. Deliberately a
	# multiplier on earnings rather than a skill-tree skip — buying your way
	# past the progression would kill the joke the game is built on.
	if owns_publisher_deal():
		awarded = int(round(awarded * (1.0 + PUBLISHER_TOKEN_BONUS)))
	# A rewarded-ad trial is worth exactly one run, and this is the end of it.
	clear_trial_unlocks()
	if distance_tiles > best_distance:
		best_distance = distance_tiles
	tokens += awarded
	stat_add("total_points_earned", awarded)
	_ensure_onboarding_funds()
	if is_daily_run:
		stat_add("daily_completed", 1)
		is_daily_run = false
	last_run_distance = distance_tiles
	add_to_library(current_run_seed, distance_tiles)
	if current_run_score > best_score_ever:
		best_score_ever = current_run_score
	_update_library_best_score(current_run_seed, current_run_score)
	save_state()
	return awarded

## Total cost of the skills the guided onboarding still asks the player to buy.
## Read from SkillsDB rather than hardcoded, so rebalancing the tree can't strand
## a new player mid-tutorial.
func onboarding_chain_cost() -> int:
	var sk = get_node_or_null("/root/SkillsDB")
	var ob = get_node_or_null("/root/Onboarding")
	if sk == null or ob == null or not ob.has_method("chain"):
		return 3
	var total := 0
	for sid in ob.chain():
		if sk.SKILLS.has(sid) and not sk.is_purchased(sid):
			total += int(sk.compute_cost(sid))
	return total

## The guide is forced, so it must always be affordable. While it is still
## running, floor the balance at what the remaining chain costs.
func _ensure_onboarding_funds() -> void:
	var ob = get_node_or_null("/root/Onboarding")
	if ob == null or not ob.has_method("is_done") or ob.is_done():
		return
	var needed := onboarding_chain_cost()
	if needed > 0 and tokens < needed:
		tokens = needed

func _update_library_best_score(seed_val: int, score: int) -> void:
	if seed_val == 0 or score <= 0: return
	for entry in level_library:
		if int(entry.get("seed", 0)) == seed_val:
			if score > int(entry.get("best_score", 0)):
				entry["best_score"] = score
			return


## ─── INPUT MAP ─────────────────────────────────────────────────────────

func _initialize_input_map() -> void:
	var input_configs: Dictionary = {
		"left":  KEY_A,
		"right": KEY_D,
		"up":    KEY_W,
		"down":  KEY_S,
		"jump":  KEY_SPACE,
		"dash":  KEY_SHIFT
	}

	print("[Global] Registering ", input_configs.size(), " input actions...")

	for action_name in input_configs:
		var already_existed = InputMap.has_action(action_name)
		if not already_existed:
			InputMap.add_action(action_name)

		var events = InputMap.action_get_events(action_name)
		if events.is_empty():
			var key_event = InputEventKey.new()
			key_event.physical_keycode = input_configs[action_name]
			InputMap.action_add_event(action_name, key_event)

	# Register stub actions the platformer controller references
	var stub_actions = ["run", "latch", "roll", "twirl"]
	for action_name in stub_actions:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

	# F3 to toggle debug overlay
	if not InputMap.has_action("toggle_debug"):
		InputMap.add_action("toggle_debug")
		var ev = InputEventKey.new()
		ev.physical_keycode = KEY_F3
		InputMap.action_add_event("toggle_debug", ev)

	# Esc to navigate back / pause
	if not InputMap.has_action("ui_back"):
		InputMap.add_action("ui_back")
		var ev = InputEventKey.new()
		ev.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("ui_back", ev)

	print("[Global] Input map fully initialised.")
