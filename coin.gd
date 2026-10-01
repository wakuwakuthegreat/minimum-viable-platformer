extends Area2D

@export var token_value: int = 1

var _collected: bool = false
var _t: float = 0.0
## Coins are placed across the entire level up front, so most of them are
## nowhere near the camera. Only the on-screen ones animate, redraw or watch for
## overlaps — without this a coin-heavy run pays for hundreds of _process calls
## and area broadphase checks every frame, which is what made it stutter.
var _notifier: VisibleOnScreenNotifier2D = null
## Coins redraw at a throttled rate: the bob/pulse is slow, so ~15fps is
## visually identical but costs a fraction of the per-frame draw calls when
## dozens of coins are on screen.
const REDRAW_INTERVAL := 1.0 / 15.0
var _redraw_timer: float = 0.0
## Frame-animated coin art, used instead of the drawn circle once sprite art is
## unlocked. Null on the primitive path, and _draw() stays empty when it exists.
var _anim: AnimatedSprite2D = null
## Set true while a drop-tween is running so the bob animation doesn't fight the tween.
## The coin draws nothing during flight and resumes bobbing once landed.
var flying: bool = false :
	set(v):
		flying = v
		if _anim != null:
			_anim.visible = not v
		if not v:
			queue_redraw()

func _ready() -> void:
	collision_layer = 0
	collision_mask = 8 | 4   # layer 8 = player body sensor, layer 4 = enemy hitboxes
	monitoring = true
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 28.0
	shape.shape = circle
	add_child(shape)
	area_entered.connect(_on_area_entered)
	add_to_group("coins")
	z_index = 5
	_setup_sprite()

	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-48, -48, 96, 96)
	_notifier.screen_entered.connect(_wake)
	_notifier.screen_exited.connect(_sleep)
	add_child(_notifier)
	_sleep()
	# The notifier only reports state after the first visibility pass, so poll
	# once for coins that spawn already on camera.
	_sync_visibility.call_deferred()

## Built once and shared by every coin — coins are the highest-frequency spawn
## in the game (several per kill), so re-loading 8 frames from disk per
## instance was the worst case of the per-spawn load() hitch (see bomb.gd's
## _boom_frames for the same fix applied to explosions).
static var _spin_frames: SpriteFrames = null

static func _get_spin_frames() -> SpriteFrames:
	if _spin_frames != null: return _spin_frames
	var frames := SpriteFrames.new()
	frames.add_animation("spin")
	for f in range(8):
		var tex: Texture2D = load("res://assets/coin-animated/BIG_000%d_Capa-%d.png" % [f, f + 1])
		if tex:
			frames.add_frame("spin", tex)
	if frames.get_frame_count("spin") == 0:
		return frames
	frames.set_animation_speed("spin", 12.0)
	frames.set_animation_loop("spin", true)
	_spin_frames = frames
	return frames

## Swap the hand-drawn circle for the 8-frame spin once sprite art is unlocked.
## Falls back to _draw() if the frames are missing so a bad asset can't make
## coins invisible.
func _setup_sprite() -> void:
	if not Global.gfx("player_sprite"): return
	var frames := _get_spin_frames()
	if frames.get_frame_count("spin") == 0:
		return
	_anim = AnimatedSprite2D.new()
	_anim.sprite_frames = frames
	# Source frames are 82x84; the drawn coin reads as a ~48px disc, so match it.
	_anim.scale = Vector2(0.6, 0.6)
	_anim.visible = not flying
	add_child(_anim)
	_anim.play("spin")

func _wake() -> void:
	if _collected: return
	set_process(true)
	set_deferred("monitoring", true)
	if _anim != null:
		_anim.play("spin")
	queue_redraw()

func _sleep() -> void:
	set_process(false)
	set_deferred("monitoring", false)
	if _anim != null:
		_anim.pause()

func _sync_visibility() -> void:
	if _collected: return
	if _notifier != null and is_instance_valid(_notifier) and _notifier.is_on_screen():
		_wake()

func _process(delta: float) -> void:
	if _collected or flying: return
	_t += delta
	rotation = sin(_t * 2.6) * 0.28
	position.y += sin(_t * 4.0) * 0.35
	# The sprite spins on its own — only the primitive coin needs redraws.
	if _anim != null: return
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_INTERVAL
		queue_redraw()

func _draw() -> void:
	if _collected or flying or _anim != null: return
	var r := 24.0 + sin(_t * 6.0) * 1.5
	draw_circle(Vector2(0, 3), r, Color(0, 0, 0, 0.25))
	draw_circle(Vector2.ZERO, r, Color(0.95, 0.78, 0.20))
	draw_arc(Vector2.ZERO, r - 4.0, 0, TAU, 32, Color(0.78, 0.55, 0.10), 2.5, true)
	draw_circle(Vector2(-r * 0.30, -r * 0.30), r * 0.20, Color(1.0, 0.96, 0.55))
	draw_arc(Vector2.ZERO, r, 0, TAU, 36, Color(0.18, 0.13, 0.05), 2.5, true)

func _on_area_entered(area: Area2D) -> void:
	if _collected or flying: return
	if area.collision_layer & 8:
		# Player body sensor.
		_collect()
	elif area.collision_layer & 4:
		# Enemy hitbox — enemy "eats" the coin.
		var enemy := area.get_parent()
		if enemy and not enemy.get("_is_dying"):
			_enemy_eat(enemy)

func _collect() -> void:
	_collected = true
	AudioManager.play("gem_gather", 0.0, 0.04)
	# A coin is always worth exactly ONE token — never two.
	Global.add_tokens_flat(1)
	TokenPop.spawn(get_parent(), global_position, 1)
	if not Global.is_unlocked("particles"):
		queue_free()
		return
	var p := CPUParticles2D.new()
	p.texture = Global.get_circle_texture()
	p.emitting = true
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, 380)
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 460.0
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.25
	p.color = Color(0.98, 0.85, 0.30)
	get_parent().add_child(p)
	p.global_position = global_position
	p.finished.connect(p.queue_free)
	queue_free()

func _enemy_eat(enemy: Node) -> void:
	_collected = true
	# Track how many coins this enemy has swallowed.
	if "coins_eaten" in enemy:
		enemy.coins_eaten += token_value
	# Brief dark-smoke dissolve — enemy absorbed the coin.
	if not Global.is_unlocked("particles"):
		queue_free()
		return
	var p := CPUParticles2D.new()
	p.texture = Global.get_circle_texture()
	p.emitting = true
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.spread = 120.0
	p.gravity = Vector2(0, -60)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 180.0
	p.scale_amount_min = 0.09
	p.scale_amount_max = 0.22
	p.color = Color(0.55, 0.45, 0.10, 0.8)
	get_parent().add_child(p)
	p.global_position = global_position
	p.finished.connect(p.queue_free)
	queue_free()
