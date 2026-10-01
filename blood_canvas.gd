extends Node2D

## Persistent blood stain layer.  Each call to add_mark() stamps a splat that
## remains for the lifetime of the level.  Capped at MAX_MARKS so memory stays
## bounded; oldest non-favorite marks are evicted first.
##
## Enable / disable via the "blood_marks" skill unlock (checked in BloodSplat).

const MAX_MARKS := 64

var _marks: Array = []   # Array of {pos: Vector2, blobs: Array of {offset, r, a}}

func add_mark(pos: Vector2, _velocity: Vector2) -> void:
	# Blob count kept low: every mark is re-drawn in full whenever a new mark
	# lands, so each blob costs draw_circle calls on that frame. Bounded here
	# so a big kill-streak can't spike the frame (worst case ~64×5 circles).
	var blob_count := randi_range(3, 5)
	var blobs: Array = []
	var spread := randf_range(18.0, 32.0)
	for _i in blob_count:
		blobs.append({
			"offset": Vector2(randf_range(-spread, spread), randf_range(-spread * 0.6, spread * 0.6)),
			"r":      randf_range(6.0, spread * 0.7),
			"a":      randf_range(0.55, 0.90),
		})
	_marks.append({"pos": pos, "blobs": blobs})
	while _marks.size() > MAX_MARKS:
		_marks.pop_front()
	queue_redraw()

func _draw() -> void:
	for mark in _marks:
		var p: Vector2 = mark["pos"]
		for blob in mark["blobs"]:
			var c := Color(0.65, 0.07, 0.07, blob["a"])
			draw_circle(p + blob["offset"], blob["r"], c)
			# Inner dark core only on larger blobs — halves the circle count.
			if blob["r"] >= 12.0:
				draw_circle(p + blob["offset"], blob["r"] * 0.38, Color(0.35, 0.03, 0.03, blob["a"] * 0.9))
