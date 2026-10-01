extends Node
class_name TokenPop

## Floating "+N ★" label that animates up and fades out.
## Static — call `TokenPop.spawn(parent, world_pos, amount)`.

## Each pop is a Label with theme overrides, which is not free to build. A coin
## arc can be swallowed in well under a second, so cap how many can be alive at
## once — past the cap the token is still credited, just silently.
const MAX_LIVE := 10
static var _live: int = 0

static func spawn(parent: Node, world_pos: Vector2, amount: int = 1) -> void:
	if parent == null or not parent.is_inside_tree(): return
	if _live >= MAX_LIVE: return
	_live += 1
	var lbl = Label.new()
	lbl.text = "+%d ★" % amount
	lbl.add_theme_color_override("font_color", Color(0.98, 0.85, 0.30))
	lbl.add_theme_color_override("font_outline_color", Color(0.18, 0.14, 0.10))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_font_size_override("font_size", 24)
	parent.add_child(lbl)
	lbl.global_position = world_pos + Vector2(-30, -40)
	lbl.z_index = 100
	lbl.tree_exiting.connect(func(): _live = max(0, _live - 1))
	var tw = lbl.create_tween().set_parallel(false)
	var pop = lbl.create_tween().set_parallel(true)
	pop.tween_property(lbl, "scale", Vector2(1.35, 1.35), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(lbl, "scale", Vector2.ONE, 0.18)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 95.0, 1.0)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.0)
	tw.tween_callback(lbl.queue_free)
