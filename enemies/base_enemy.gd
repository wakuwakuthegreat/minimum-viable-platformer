extends CharacterBody2D
class_name BaseEnemy

@export var can_be_stomped: bool = true
@export var gravity_scale: float = 1.0
## Bonus multiplier added to the combo when stomped. 0 = plain enemy, 2 = bouncy,
## 10 = super-bouncy trampoline enemy. Subclasses override in _ready().
@export var combo_bonus: int = 1.5

## ── Tear-death configuration ───────────────────────────────────────────────
## Set these in each subclass _ready() to match the entity's visual size and colour.
@export var tear_size:  Vector2 = Vector2(64, 64)
@export var tear_color: Color   = Color(0.55, 0.55, 0.55)
@export var tear_type:  String  = "default"
## Optional local-space Vector2 coords that bias tear cut angles.
var tear_hard_points: Array = []
## Set false on entities that should poof (not tear) even on contact death (e.g. bullet).
var tears_on_death: bool = true

var player: Node2D = null
var _is_dying: bool = false

## Coins this enemy has eaten during the run (see coin.gd _enemy_eat).
var coins_eaten: int = 0

# ── Enemy drop configuration (easy to tune) ────────────────────────────
## Minimum forward distance (px) coins fly from the death spot.
const DROP_FORWARD_MIN := 120.0
## Maximum forward distance (px).
const DROP_FORWARD_MAX := 340.0
## Minimum upward offset (px, negative = up).
const DROP_UP_MIN      := -180.0
## Maximum upward offset (px, negative = up).
const DROP_UP_MAX      := -440.0
## Extra random horizontal spread (px) per coin so they fan out.
const DROP_SPREAD_X    := 70.0
## Tween duration (seconds) for the arc flight.
const DROP_TWEEN_SECS  := 0.30

## Preloaded, not load()-ed per death — every enemy in a kill chain used to hit
## disk/the resource cache for this on its way out (see bomb.gd's _boom_frames
## for the same class of hitch with explosion frames).
const COIN_SCENE := preload("res://coin.tscn")

func _ready() -> void:
	collision_layer = 2  # Enemies on Layer 2
	# Mask 3 = Layer 1 (floor) + Layer 2 (other enemies) — enemies collide with each other
	collision_mask  = 3
	
	# Hitbox Area2D only for detecting the PLAYER hitting us from the side/below
	var hitbox = $Hitbox
	if hitbox:
		hitbox.collision_layer = 4   # Hitbox on Layer 4
		hitbox.collision_mask  = 8   # Detect Layer 8 (player body sensor)
		hitbox.area_entered.connect(_on_hitbox_area_entered)

func _find_player() -> void:
	if player: return
	var p = Global.player;#().get_node_or_null("Player")
	if p: player = p

func _physics_process(delta: float) -> void:
	if _is_dying:
		return
	_find_player()
	velocity.y += 980 * gravity_scale * delta
	_custom_process(delta)
	move_and_slide()
	_check_player_contact()
	if Global.debug_toggles.get("show_collisions", false):
		queue_redraw()

## Continuous (level-triggered) contact check. body/area_entered only fire on the
## FRAME an overlap begins, so an overlap that already existed (enemy spawned on
## the player, monitoring toggled, etc.) is silently missed. Re-running the hit
## logic each physics frame for whatever currently overlaps closes that hole.
func _check_player_contact() -> void:
	if _is_dying: return
	var hb = get_node_or_null("Hitbox")
	if hb == null or not hb.monitoring: return
	for a in hb.get_overlapping_areas():
		_on_hitbox_area_entered(a)

func _custom_process(_delta: float) -> void:
	pass

# Called by the player's FOOT sensor — always a stomp
func stomp_by(stomper: Node2D) -> void:
	if _is_dying: return
	die()
	var body_vel = stomper.get("velocity")
	if body_vel is Vector2:
		stomper.set("velocity", Vector2(body_vel.x, -900)) # Big bounce
		# Always restore one jump so the player can chain stomps even without double-jump.
		var jumps_total = stomper.get("jumps")
		if jumps_total != null and int(jumps_total) >= 1:
			stomper.set("jumpCount", 1)

# Called when player body sensor overlaps our hitbox.
# Frogs, kobolds and bats KILL the player from any direction EXCEPT from the head.
# "From the head" = player centre is clearly above our centre (they are stomping).
# The foot sensor handles the stomp; we just skip the kill here.
func _on_hitbox_area_entered(area: Area2D) -> void:
	if _is_dying: return
	var body = area.get_parent()
	if body and body.has_method("die") and not body.get("is_dead"):
		# Genuine stomp (player descending onto us from above) → the foot sensor
		# handles the bounce; we must NOT kill. Everything else — side hits and
		# something dropping onto the player's head — is lethal.
		if body.has_method("is_stomp_on"):
			if body.is_stomp_on(global_position.y):
				return
		elif body.global_position.y < global_position.y - 30:
			return
		# The player just parried something → phasing through, invulnerable.
		if body.has_method("is_parry_invuln") and body.is_parry_invuln():
			return
		# Un-parried contact is always lethal (the look-ahead scan already gave
		# the parry chance BEFORE this point).
		body.die(false, _display_name())


## Human-readable name used for "Killed by …" messages. Subclasses can override.
func _display_name() -> String:
	var s = get_script()
	if s:
		var stem = s.resource_path.get_file().get_basename()
		return "a " + stem.replace("_", " ")
	return "an enemy"

## Normal kill – poof particles. Pass torn=true to shatter into physics pieces.
## impact_vel is used to scatter pieces outward.
func die(torn: bool = false, impact_vel = Vector2.ZERO, instant_shatter: bool = false) -> void:
	if _is_dying: return
	if not impact_vel is Vector2:
		impact_vel = Vector2.ZERO

	_is_dying = true

	# Blood splat lives one level up so it survives our queue_free().
	# Bullets don't bleed — they're inert projectiles.
	var script_res = get_script()
	var is_bullet = script_res != null and script_res.resource_path.contains("bullet")
	if not is_bullet:
		BloodSplat.apply(get_parent(), global_position, impact_vel)

	if torn and tears_on_death:
		# Shatter into irregular physics polygons
		TearEffect.apply(self, tear_size, tear_color, impact_vel, tear_hard_points, tear_type)
	elif Global.is_unlocked("particles") or Global.is_unlocked("party_death"):
		# Classic poof (Party Mode is its own unlock, so it also earns the burst)
		var poof = CPUParticles2D.new()
		poof.texture = Global.get_circle_texture()
		poof.emitting = true
		poof.one_shot = true
		poof.amount = 24
		poof.lifetime = 0.5
		poof.explosiveness = 1.0
		poof.spread = 180.0
		poof.initial_velocity_min = 80.0
		poof.initial_velocity_max = 280.0
		poof.scale_amount_min = 0.12   # 8–26 px
		poof.scale_amount_max = 0.4
		poof.color = Color(0.9, 0.9, 0.9)
		# Party Mode unlock: death bursts into multicoloured confetti.
		if Global.is_unlocked("party_death"):
			poof.amount = 44
			poof.initial_velocity_max = 360.0
			var grad := Gradient.new()
			grad.set_color(0, Color.from_hsv(randf(), 0.85, 1.0))
			grad.set_color(1, Color.from_hsv(randf(), 0.85, 1.0))
			grad.add_point(0.5, Color.from_hsv(randf(), 0.85, 1.0))
			poof.color_ramp = grad
			poof.color = Color.WHITE
		get_parent().add_child(poof)
		poof.global_position = global_position
		poof.finished.connect(poof.queue_free)

	if Global.is_unlocked("enemy_drops") and not is_bullet:
		_spawn_coin_drops()
	elif Global.is_unlocked("midas_touch") and not is_bullet:
		# Midas Touch: even without Enemy Drops, every kill coughs up gold.
		_spawn_coin_drops(true)

	queue_free()

## Weighted random: drop 0–5 extra coins + any coins previously eaten.
## Weights: [0]=55 [1]=25 [2]=12 [3]=5 [4]=2 [5]=1  — zero is heavily favoured to avoid screen clutter.
func _spawn_coin_drops(guaranteed: bool = false) -> void:
	const WEIGHTS := [55, 25, 12, 5, 2, 1]
	var roll := randi() % 100
	var extra := 0
	var acc := 0
	for w in WEIGHTS:
		acc += w
		if roll < acc: break
		extra += 1

	# Midas Touch guarantees a healthy pile regardless of the weighted roll.
	if guaranteed or Global.is_unlocked("midas_touch"):
		extra = max(extra, 3)

	var total := coins_eaten + extra
	coins_eaten = 0
	if total <= 0: return

	var parent := get_parent()
	if parent == null: return

	for k in total:
		var c = COIN_SCENE.instantiate()
		parent.add_child(c)
		c.global_position = global_position
		c.flying = true
		# Target: forward and upward, randomised per coin.
		var tx := global_position.x + randf_range(DROP_FORWARD_MIN, DROP_FORWARD_MAX) \
				  + randf_range(-DROP_SPREAD_X, DROP_SPREAD_X)
		var ty := global_position.y + randf_range(DROP_UP_MIN, DROP_UP_MAX)
		# Brief delay per coin so they fan out in time.
		var delay := k * 0.04
		var tw = c.create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if delay > 0.0:
			tw.tween_interval(delay)
		tw.tween_property(c, "global_position", Vector2(tx, ty), DROP_TWEEN_SECS)
		tw.tween_callback(func(): if is_instance_valid(c): c.flying = false)

## Convenience shorthand – call this when an impact velocity is known.
func die_torn(impact_vel: Vector2 = Vector2.ZERO) -> void:
	die(true, impact_vel)
