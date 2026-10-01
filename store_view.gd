extends CanvasLayer

## In-game token store. Replaces RevenueCat's native paywall, which looked like
## a different app bolted on. Same warm cream / ink / pumpkin palette as
## UITheme's polished look, and it is always drawn that way — this screen takes
## real money, so it never wears the deliberately drab placeholder theme.
##
## Open from anywhere:
##     StoreView.open(self)
## Everything is built in code and styled locally; UITheme.apply is never run
## over it, so the unlockable font / theme choices can't restyle a checkout.

class_name StoreView

signal closed

const FONT_KA1 := preload("res://assets/fonts/ka1.ttf")
const StatIcon := preload("res://stat_icon.gd")

const COL_PAPER      := Color(0.99, 0.92, 0.80)
const COL_CARD       := Color(1.00, 0.97, 0.90)
const COL_CARD_HOT   := Color(1.00, 0.88, 0.70)
const COL_INK        := Color(0.18, 0.14, 0.10)
const COL_INK_SOFT   := Color(0.18, 0.14, 0.10, 0.72)
const COL_PUMPKIN    := Color(0.95, 0.55, 0.20)
const COL_PUMPKIN_HI := Color(1.00, 0.74, 0.32)
const COL_GRASS      := Color(0.60, 0.78, 0.32)
const COL_GRASS_DARK := Color(0.36, 0.50, 0.20)

## Catalogue. `art` picks the drawing in CardArt; `tokens` is display-only —
## the real grant lives in IAP.TOKEN_PACK_GRANTS so the two can never disagree
## about what was paid for (it is read from there below).
const ITEMS := [
	{"id": "tokens_small", "name": "Pocket Change", "art": "coins_small",
		"blurb": "A few upgrades' worth. Skip a handful of deaths."},
	{"id": "tokens_large", "name": "Venture Round", "art": "coins_large", "tag": "BEST VALUE",
		"blurb": "The investors would like a finished platformer by Friday."},
	{"id": "publisher_deal", "name": "Publisher Deal", "art": "contract", "tag": "PERMANENT",
		"blurb": "Every run pays out more. Forever. Do not read the contract."},
	{"id": "developer_support", "name": "Tip the Dev", "art": "heart",
		"blurb": "A real person made this. They would like a sandwich."},
]

var _dim: ColorRect
var _sheet: PanelContainer
var _grid: GridContainer
var _balance_lbl: Label
var _toast_lbl: Label
var _restore_btn: Button
## product id -> Button, so prices and owned state can be refreshed in place.
var _buy_btns: Dictionary = {}
var _busy: bool = false
var _closing: bool = false


static func open(from: Node) -> StoreView:
	var v := StoreView.new()
	# Deferred: callers may be mid-_ready, when root refuses new children.
	from.get_tree().root.add_child.call_deferred(v)
	return v


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_refresh()
	IAP.prices_updated.connect(_refresh)
	IAP.entitlements_changed.connect(_refresh)
	IAP.purchase_succeeded.connect(_on_purchase_succeeded)
	IAP.purchase_failed.connect(_on_purchase_failed)
	IAP.fetch_prices()
	get_viewport().size_changed.connect(_fit)
	_fit()
	AudioManager.connect_ui_clicks(self)
	_play_in()


# ─── BUILD ───────────────────────────────────────────────────────────────

func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.10, 0.06, 0.04, 0.72)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(e: InputEvent):
		# Tapping the backdrop closes, like every other sheet on a phone.
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			close())
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_sheet = PanelContainer.new()
	_sheet.add_theme_stylebox_override("panel", _box(COL_PAPER, COL_INK, 4, 26, 26, 14))
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_sheet)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	_sheet.add_child(v)

	v.add_child(_build_header())

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	v.add_child(_grid)
	for item in ITEMS:
		_grid.add_child(_build_card(item))

	v.add_child(_build_footer())


func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	h.add_child(titles)

	var title := _label("TOKEN EXCHANGE", 38, COL_INK)
	title.add_theme_font_override("font", FONT_KA1)
	title.add_theme_color_override("font_outline_color", COL_PUMPKIN_HI)
	title.add_theme_constant_override("outline_size", 6)
	titles.add_child(title)
	titles.add_child(_label("Monetize your suffering. Now with a faster lane.", 18, COL_INK_SOFT))

	# Balance chip — ink pill, same shape language as the HUD token counter.
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", _box(COL_INK, COL_INK, 0, 22, 14, 0))
	var chip_h := HBoxContainer.new()
	chip_h.add_theme_constant_override("separation", 6)
	chip.add_child(chip_h)
	var star := StatIcon.new()
	star.kind = StatIcon.Kind.STAR
	star.accent = COL_PUMPKIN_HI
	star.color = COL_PAPER
	star.custom_minimum_size = Vector2(28, 28)
	chip_h.add_child(star)
	_balance_lbl = _label("0", 24, COL_PAPER)
	chip_h.add_child(_balance_lbl)
	h.add_child(chip)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(56, 56)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.add_theme_font_size_override("font_size", 28)
	_style_button(close_btn, COL_CARD, COL_PUMPKIN_HI, 28)
	close_btn.pressed.connect(close)
	h.add_child(close_btn)
	return h


func _build_card(item: Dictionary) -> Control:
	var pid := String(item["id"])
	var hot := item.has("tag")
	var accent := COL_GRASS_DARK if pid == IAP.PRODUCT_PUBLISHER_DEAL else COL_PUMPKIN
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(230, 0)
	card.add_theme_stylebox_override("panel", _box(
		COL_CARD_HOT if hot else COL_CARD,
		accent if hot else COL_INK, 3, 18, 14, 6))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	# Tag ribbon, or an equally tall spacer so every card's art lines up.
	var tag_row := CenterContainer.new()
	tag_row.custom_minimum_size = Vector2(0, 26)
	v.add_child(tag_row)
	if hot:
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", _box(accent, accent, 0, 10, 10, 0, 2))
		tag.add_child(_label(String(item["tag"]), 14, Color.WHITE))
		tag_row.add_child(tag)

	var art := CardArt.new()
	art.kind = String(item["art"])
	art.custom_minimum_size = Vector2(0, 92)
	v.add_child(art)

	var name_lbl := _label(String(item["name"]), 24, COL_INK)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_lbl)

	var amount := ""
	if IAP.TOKEN_PACK_GRANTS.has(pid):
		amount = "+%d ★" % int(IAP.TOKEN_PACK_GRANTS[pid])
	else:
		amount = "+50% ★ / run"
	var amount_lbl := _label(amount, 26, COL_PUMPKIN.darkened(0.25))
	amount_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(amount_lbl)

	var blurb := _label(String(item["blurb"]), 16, COL_INK_SOFT)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blurb.custom_minimum_size = Vector2(190, 0)
	v.add_child(blurb)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(0, 58)
	buy.add_theme_font_size_override("font_size", 24)
	_style_button(buy, COL_PUMPKIN_HI, COL_PUMPKIN, 16)
	buy.pressed.connect(_on_buy.bind(pid))
	v.add_child(buy)
	_buy_btns[pid] = buy
	return card


func _build_footer() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)

	_toast_lbl = _label("", 20, COL_INK)
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_lbl.modulate.a = 0.0
	v.add_child(_toast_lbl)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)

	_restore_btn = Button.new()
	_restore_btn.text = "Restore purchases"
	_restore_btn.flat = true
	_restore_btn.add_theme_font_size_override("font_size", 18)
	_restore_btn.add_theme_color_override("font_color", COL_INK)
	_restore_btn.add_theme_color_override("font_hover_color", COL_PUMPKIN.darkened(0.2))
	_restore_btn.add_theme_color_override("font_pressed_color", COL_PUMPKIN)
	_restore_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_restore_btn.pressed.connect(_on_restore)
	h.add_child(_restore_btn)

	var fine := _label("Everything here can also be earned by dying. Tokens only make it faster.", 15, COL_INK_SOFT)
	fine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fine.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(fine)
	return v


## Two columns on narrow / tall screens, four across on a landscape phone.
func _fit() -> void:
	var vp := get_viewport().get_visible_rect().size
	_grid.columns = 4 if vp.x >= 1100.0 else 2
	_sheet.custom_minimum_size = Vector2(min(vp.x - 32.0, 1180.0), 0)


# ─── STATE ───────────────────────────────────────────────────────────────

func _refresh() -> void:
	_balance_lbl.text = str(Global.tokens)
	for pid in _buy_btns:
		var b: Button = _buy_btns[pid]
		if pid == IAP.PRODUCT_PUBLISHER_DEAL and Global.owns_publisher_deal():
			b.text = "Signed ✓"
			b.disabled = true
			_style_button(b, COL_GRASS, COL_GRASS, 16)
			continue
		var price := IAP.price_for(pid)
		b.text = price if price != "" else "Buy"
		b.disabled = _busy


func _on_buy(pid: String) -> void:
	if _busy: return
	if not IAP.available:
		AudioManager.play("ui_glass", -4.0, 0.05)
		_toast("The store isn't available on this build.")
		return
	_set_busy(true)
	IAP.purchase(pid)
	# The plugin should always answer, but never leave the buttons dead if a
	# native callback goes missing. A connection (not an await) so closing the
	# sheet mid-purchase just drops it.
	get_tree().create_timer(30.0).timeout.connect(_on_busy_timeout)


func _on_busy_timeout() -> void:
	if _busy: _set_busy(false)


func _set_busy(on: bool) -> void:
	_busy = on
	_refresh()
	if on:
		_toast("Talking to the store…", 30.0)


func _on_purchase_succeeded(pid: String) -> void:
	_set_busy(false)
	AudioManager.play("ui_buy", 0.0, 0.04)
	if IAP.TOKEN_PACK_GRANTS.has(pid):
		_toast("+%d ★ — pleasure doing business." % int(IAP.TOKEN_PACK_GRANTS[pid]))
	elif pid == IAP.PRODUCT_PUBLISHER_DEAL:
		_toast("Contract signed. Every run now pays +50%.")
	else:
		_toast("Thank you!")
	_refresh()
	var tw := create_tween()
	_balance_lbl.pivot_offset = _balance_lbl.size * 0.5
	tw.tween_property(_balance_lbl, "scale", Vector2(1.4, 1.4), 0.10).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_balance_lbl, "scale", Vector2.ONE, 0.20)


func _on_purchase_failed(reason: String) -> void:
	_set_busy(false)
	if reason == "Cancelled":
		_toast("")
		return
	AudioManager.play("ui_glass", -4.0, 0.05)
	_toast("That didn't go through. Nothing was charged." if reason == "" else reason)


func _on_restore() -> void:
	if not IAP.available:
		_toast("The store isn't available on this build.")
		return
	_restore_btn.disabled = true
	_toast("Checking your receipts…", 25.0)
	IAP.restore_finished.connect(_on_restore_finished, CONNECT_ONE_SHOT)
	IAP.restore()


func _on_restore_finished(ok: bool) -> void:
	_restore_btn.disabled = false
	_toast("Purchases restored." if ok else "Nothing to restore.")
	_refresh()


# ─── OPEN / CLOSE ────────────────────────────────────────────────────────

func _play_in() -> void:
	_dim.modulate.a = 0.0
	_sheet.modulate.a = 0.0
	_sheet.scale = Vector2(0.9, 0.9)
	await get_tree().process_frame
	if not is_instance_valid(self): return
	_sheet.pivot_offset = _sheet.size * 0.5
	var tw := create_tween().set_parallel()
	tw.tween_property(_dim, "modulate:a", 1.0, 0.2)
	tw.tween_property(_sheet, "modulate:a", 1.0, 0.2)
	tw.tween_property(_sheet, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if _closing: return
	_closing = true
	_sheet.pivot_offset = _sheet.size * 0.5
	var tw := create_tween().set_parallel()
	tw.tween_property(_dim, "modulate:a", 0.0, 0.15)
	tw.tween_property(_sheet, "modulate:a", 0.0, 0.15)
	tw.tween_property(_sheet, "scale", Vector2(0.94, 0.94), 0.15)
	tw.chain().tween_callback(func():
		closed.emit()
		queue_free())


func _input(event: InputEvent) -> void:
	# Added last under root, so this runs before the host screen's own
	# back-handler (which on the main menu would quit the game).
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# ─── HELPERS ─────────────────────────────────────────────────────────────

var _toast_tw: Tween = null

func _toast(msg: String, hold: float = 2.6) -> void:
	if _toast_tw and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_lbl.text = msg
	_toast_lbl.modulate.a = 1.0 if msg != "" else 0.0
	if msg == "": return
	_toast_tw = create_tween()
	_toast_tw.tween_interval(hold)
	_toast_tw.tween_property(_toast_lbl, "modulate:a", 0.0, 0.4)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _box(bg: Color, border: Color, border_w: int, radius: int, pad: int,
		shadow: int, pad_v: int = -1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad if pad_v < 0 else pad_v
	sb.content_margin_bottom = pad if pad_v < 0 else pad_v
	if shadow > 0:
		sb.shadow_color = Color(0, 0, 0, 0.28)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, 4)
	return sb


## Chunky ink-outlined button, the same shape as UITheme's polished buttons.
func _style_button(b: Button, bg: Color, hover: Color, radius: int) -> void:
	var normal := _box(bg, COL_INK, 3, radius, 12, 4, 6)
	var hov := _box(hover, COL_INK, 3, radius, 12, 6, 6)
	var press := _box(hover.darkened(0.12), COL_INK, 3, radius, 12, 1, 6)
	var dis := _box(bg.lerp(Color(0.6, 0.6, 0.6), 0.35), COL_INK_SOFT, 3, radius, 12, 0, 6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", press)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, COL_INK)
	b.add_theme_color_override("font_disabled_color", COL_INK_SOFT)


## Hand-drawn product art — coins, a contract, a heart — in the same flat
## ink-outline style as stat_icon.gd, so no texture assets are needed.
class CardArt extends Control:
	var kind: String = "coins_small"

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		match kind:
			"coins_small":
				_coin_stack(c + Vector2(-26, 22), 3)
				_coin_stack(c + Vector2(22, 26), 2)
			"coins_large":
				_coin_stack(c + Vector2(-50, 28), 4)
				_coin_stack(c + Vector2(0, 30), 6)
				_coin_stack(c + Vector2(48, 28), 3)
				_sparkle(c + Vector2(40, -30), 9.0)
				_sparkle(c + Vector2(-44, -18), 6.0)
			"contract":
				_contract(c)
			"heart":
				_heart(c, 30.0)

	func _coin_stack(base: Vector2, n: int) -> void:
		for i in n:
			_coin(base + Vector2(0, -i * 9.0), i == n - 1)

	func _coin(p: Vector2, top: bool) -> void:
		# Squashed circles read as coins lying flat.
		var rx := 22.0
		var ry := 8.0
		var rim := PackedVector2Array()
		var face := PackedVector2Array()
		for i in 24:
			var a := TAU * float(i) / 24.0
			face.append(p + Vector2(cos(a) * rx, sin(a) * ry))
			rim.append(p + Vector2(cos(a) * rx, sin(a) * ry + 4.0))
		draw_colored_polygon(rim, COL_PUMPKIN.darkened(0.2))
		draw_colored_polygon(face, COL_PUMPKIN_HI)
		face.append(face[0])
		draw_polyline(face, COL_INK, 2.0, true)
		if top:
			draw_line(p + Vector2(-8, 0), p + Vector2(8, 0), COL_INK, 2.0)

	func _sparkle(p: Vector2, r: float) -> void:
		var pts := PackedVector2Array()
		for i in 8:
			var a := TAU * float(i) / 8.0 - PI / 2.0
			pts.append(p + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.3))
		draw_colored_polygon(pts, Color.WHITE)
		pts.append(pts[0])
		draw_polyline(pts, COL_INK, 1.5, true)

	func _contract(c: Vector2) -> void:
		var r := Rect2(c + Vector2(-30, -40), Vector2(60, 80))
		draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(0, 0, 0, 0.18))
		draw_rect(r, Color.WHITE)
		draw_rect(r, COL_INK, false, 2.5)
		for i in 5:
			var y := r.position.y + 14.0 + i * 10.0
			var w := 40.0 if i < 4 else 24.0
			draw_line(Vector2(r.position.x + 10, y), Vector2(r.position.x + 10 + w, y), COL_INK_SOFT, 2.0)
		# Wax seal.
		var seal := c + Vector2(20, 30)
		draw_circle(seal, 13.0, Color(0.80, 0.22, 0.20))
		draw_arc(seal, 13.0, 0, TAU, 24, COL_INK, 2.0, true)
		draw_circle(seal, 5.0, Color(0.95, 0.45, 0.40))

	func _heart(c: Vector2, s: float) -> void:
		var pts := PackedVector2Array()
		for i in 48:
			var t := TAU * float(i) / 48.0
			var x := 16.0 * pow(sin(t), 3)
			var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
			pts.append(c + Vector2(x, y) * (s / 16.0))
		draw_colored_polygon(pts, Color(0.93, 0.36, 0.42))
		pts.append(pts[0])
		draw_polyline(pts, COL_INK, 2.5, true)
		draw_circle(c + Vector2(-s * 0.45, -s * 0.35), s * 0.14, Color(1, 1, 1, 0.7))
