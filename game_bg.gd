extends CanvasLayer

## In-game background. Always shows SOMETHING. Layered:
##   * flat warm gradient (always)
##   * far hills (parallax unlocked) — slow scroll
##   * near hills (parallax unlocked) — fast scroll
##   * camera-x driven so the layers move when the player runs

@onready var bg: Control = $BG
@onready var clouds: Control = $BG/Clouds
@onready var hills_far: Control = $BG/HillsFar
@onready var hills_near: Control = $BG/HillsNear

var _cam: Camera2D = null
var _hill_seeds: Array[float] = []

func _ready() -> void:
	layer = -100
	# Fill the seeds for stable per-instance hill shape
	var rng = RandomNumberGenerator.new()
	rng.seed = 9001
	for i in 96:
		_hill_seeds.append(rng.randf())
	bg.set_meta("seeds", _hill_seeds)
	hills_far.set_meta("seeds", _hill_seeds)
	hills_near.set_meta("seeds", _hill_seeds)
	bg.queue_redraw()
	hills_far.visible = Global.is_unlocked("parallax")
	hills_near.visible = Global.is_unlocked("parallax")
	clouds.visible = Global.is_unlocked("clouds")

var _last_cam_x: float = INF

func _process(_delta: float) -> void:
	# Track player camera so layers can parallax with x.
	if not is_instance_valid(_cam):
		_cam = _find_cam()
	if _cam:
		var x = _cam.global_position.x
		# Hills only move with the camera — skip the polygon rebuild on frames
		# where it hasn't moved (death card, pauses, standing still).
		if hills_far.visible and x != _last_cam_x:
			_last_cam_x = x
			hills_far.set_meta("scroll_x", x * 0.10)
			hills_near.set_meta("scroll_x", x * 0.35)
			hills_far.queue_redraw()
			hills_near.queue_redraw()
		if clouds.visible:
			clouds.set_meta("scroll_x", x * 0.05 + Time.get_ticks_msec() * 0.02)
			clouds.queue_redraw()

func _find_cam() -> Camera2D:
	var vp = get_viewport()
	if vp and vp.get_camera_2d():
		return vp.get_camera_2d()
	return null
