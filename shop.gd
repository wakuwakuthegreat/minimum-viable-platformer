extends CanvasLayer

@onready var tokens_label: Label = $Root/TopBar/TokensLabel
@onready var title_label: Label = $Root/TopBar/Title
@onready var back_btn: Button = $Root/TopBar/BackButton
@onready var tree_view: Control = $Root/Body/Tree
@onready var detail_panel: Panel = $Root/Body/Detail
@onready var d_name: Label = $Root/Body/Detail/Scroll/V/Name
@onready var d_desc: Label = $Root/Body/Detail/Scroll/V/Desc
@onready var d_cost: Label = $Root/Body/Detail/Scroll/V/Cost
@onready var d_status: Label = $Root/Body/Detail/Scroll/V/Status
@onready var d_buy: Button = $Root/Body/Detail/Scroll/V/BuyButton
@onready var d_branch: Label = $Root/Body/Detail/Scroll/V/Branch
@onready var legend: HBoxContainer = $Root/Legend

## Dynamically created toggle checkbox; shown only for purchased skills.
var _d_toggle: CheckBox = null
var _d_toggle_hint: Label = null

## Recommend button — cycles the tree camera through purchasable skills in
## priority order. Only visible while there's something left to buy.
var _recommend_btn: Button = null
## Snapshot of the current cycle so successive clicks step through the same
## ordered list until it's exhausted or state changes (buy/spend). Rebuilt
## lazily by _current_recommendations() when stale.
var _recommend_cycle: Array = []
var _recommend_idx: int = -1
var _recommend_state_sig: String = ""

## "Get tokens" — opens the in-game store. Lives in the top bar next to the
## token count, which is exactly where a player looks when they are short.
var _store_btn: Button = null
## "Watch to try" — lends the selected skill for one run. Appended to the detail
## panel, shown only for a skill the player can't afford yet.
var _d_trial_btn: Button = null

func _ready() -> void:
	layer = 95
	back_btn.pressed.connect(_on_back)
	d_buy.pressed.connect(_on_buy)
	tree_view.skill_selected.connect(_on_skill_selected)
	UITheme.apply_current(self)
	legend.visible = false

	# Recommend button — inserted before the tokens label so it sits right of
	# the title. Hidden by _refresh when nothing is purchasable.
	_recommend_btn = Button.new()
	_recommend_btn.text = "Recommend"
	_recommend_btn.custom_minimum_size = Vector2(180, 0)
	_recommend_btn.add_theme_font_size_override("font_size", 22)
	_recommend_btn.pressed.connect(_on_recommend)
	var top_bar := $Root/TopBar
	top_bar.add_child(_recommend_btn)
	top_bar.move_child(_recommend_btn, tokens_label.get_index())
	UITheme.apply_current(_recommend_btn)

	# Store button — the paywall entry point, sitting immediately left of the
	# token count so "I need more tokens" and "here is how" are the same glance.
	_store_btn = Button.new()
	_store_btn.text = "＋ Tokens"
	_store_btn.custom_minimum_size = Vector2(150, 0)
	_store_btn.add_theme_font_size_override("font_size", 22)
	_store_btn.pressed.connect(_on_store)
	# Hidden where no store can ever exist (web/desktop release builds), so a
	# web player never meets a button whose only reply is "unavailable".
	# Debug builds keep it visible so the layout is checkable on PC.
	_store_btn.visible = IAP.available or OS.is_debug_build()
	top_bar.add_child(_store_btn)
	top_bar.move_child(_store_btn, tokens_label.get_index())
	UITheme.apply_current(_store_btn)

	# Create the active-toggle checkbox and append it to the detail VBox.
	var detail_vbox = $Root/Body/Detail/Scroll/V

	# Rewarded-ad trial button, appended below Buy. Visibility is owned by
	# _refresh_detail — it only appears on a skill that is unaffordable but
	# otherwise ready to buy.
	_d_trial_btn = Button.new()
	_d_trial_btn.text = "▶ Watch to try for one run"
	_d_trial_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_trial_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_trial_btn.visible = false
	_d_trial_btn.pressed.connect(_on_trial)
	detail_vbox.add_child(_d_trial_btn)
	detail_vbox.move_child(_d_trial_btn, d_buy.get_index() + 1)
	UITheme.apply_current(_d_trial_btn)

	IAP.entitlements_changed.connect(_refresh)
	IAP.purchase_succeeded.connect(func(_pid: String): _refresh())
	_d_toggle = CheckBox.new()
	_d_toggle.text = "Feature active"
	_d_toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_toggle.visible = false
	detail_vbox.add_child(_d_toggle)
	_d_toggle.toggled.connect(func(p: bool):
		AudioManager.play("switch_on" if p else "switch_off", 0.0, 0.04)
		_on_toggle_active(p)
	)

	_d_toggle_hint = Label.new()
	_d_toggle_hint.text = "Uncheck to disable without losing progress."
	_d_toggle_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_toggle_hint.add_theme_font_size_override("font_size", 14)
	_d_toggle_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_toggle_hint.visible = false
	detail_vbox.add_child(_d_toggle_hint)

	# The toggle & hint were created after UITheme.apply_current ran above, so
	# re-apply so the switch icons + polished label colors reach them.
	UITheme.apply_current(_d_toggle)
	UITheme.apply_current(_d_toggle_hint)

	# Description label needs to wrap inside the narrow detail panel.
	d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Force dark ink on all detail-panel labels so the description never renders
	# with a light theme fallback (the placeholder theme paints Labels white).
	var ink := Color(0.15, 0.10, 0.06)
	for lbl in [d_name, d_desc, d_cost, d_status, d_branch]:
		lbl.add_theme_color_override("font_color", ink)
		lbl.add_theme_color_override("font_outline_color", Color(1.0, 0.95, 0.82))
		lbl.add_theme_constant_override("outline_size", 3)
	# Bump descriptor/status size a touch so it isn't a footnote.
	d_desc.add_theme_font_size_override("font_size", 20)
	d_status.add_theme_font_size_override("font_size", 20)
	d_cost.add_theme_font_size_override("font_size", 20)
	d_branch.add_theme_font_size_override("font_size", 18)

	_refresh()
	# Select root by default so the detail panel isn't empty.
	tree_view.set_selected(SkillsDB.ROOT_ID)
	_on_skill_selected(SkillsDB.ROOT_ID)
	AudioManager.play_music("shop", 1.2)
	# Visiting the shop resets the enemy guide's "dodging the shop" streak.
	Global.runs_since_shop = 0
	Global.save_state_deferred()
	AudioManager.connect_ui_clicks(self)
	# Forced guide: patter, pans the tree, then points at the node. No-ops after.
	Onboarding.attach.call_deferred(self, "shop")
	_play_pending_cut.call_deferred("shop_open")


## Fire any ambient StoryDB scene queued for this screen (purchase reactions,
## the passive-aggressive nudge when tokens pile up). Skipped while the guide runs.
func _play_pending_cut(at: String) -> void:
	var scene: Dictionary = StoryDB.pending(at)
	if scene.is_empty(): return
	var cut = preload("res://story_cut.gd").new()
	get_tree().root.add_child(cut)
	cut.play(scene.get("blocks", []), String(scene.get("mode", "black")))
	StoryDB.mark_seen(scene)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		_on_back()

func _refresh() -> void:
	tokens_label.text = "★  %d tokens" % Global.tokens
	title_label.text  = "Skill Tree"
	tree_view.queue_redraw()
	_refresh_detail()
	_refresh_recommend_btn()

## Snapshot signature of the "purchasable now" set. When it changes (buy,
## afford, prereq newly met), we invalidate the cycle so the button steps
## through a fresh list.
func _recommend_signature() -> String:
	var ids := SkillsDB.SKILLS.keys()
	ids.sort()
	var parts := PackedStringArray()
	for sid in ids:
		if SkillsDB.purchasable_now(sid):
			parts.append(sid)
	parts.append("$T=%d" % Global.tokens)
	return "|".join(parts)

## Build the ordered recommendation list. Priority DESC breaks by depth ASC
## (shallower nodes first — they unlock more branches) then id ASC for stable
## order. Only returns skills the player can buy right now.
func _build_recommend_cycle() -> Array:
	var items: Array = []
	for sid in SkillsDB.SKILLS.keys():
		if not SkillsDB.purchasable_now(sid): continue
		var pr: int = SkillsDB.get_priority(sid)
		var depth: int = SkillsDB.depth_from_root(sid)
		items.append({"sid": sid, "priority": pr, "depth": depth})
	items.sort_custom(func(a, b):
		if a.priority != b.priority: return a.priority > b.priority
		if a.depth != b.depth: return a.depth < b.depth
		return a.sid < b.sid)
	var out: Array = []
	for it in items:
		out.append(it.sid)
	return out

## Current cycle, rebuilt if the purchasable set has changed since last time.
func _current_recommendations() -> Array:
	var sig := _recommend_signature()
	if sig != _recommend_state_sig:
		_recommend_state_sig = sig
		_recommend_cycle = _build_recommend_cycle()
		_recommend_idx = -1
	return _recommend_cycle

func _refresh_recommend_btn() -> void:
	if _recommend_btn == null: return
	var recs := _current_recommendations()
	if recs.is_empty():
		_recommend_btn.visible = false
	else:
		_recommend_btn.visible = true
		_recommend_btn.text = "★ Recommend (%d)" % recs.size()

func _on_recommend() -> void:
	var recs := _current_recommendations()
	if recs.is_empty(): return
	_recommend_idx = (_recommend_idx + 1) % recs.size()
	var sid: String = recs[_recommend_idx]
	if tree_view.has_method("focus_on"):
		tree_view.focus_on(sid)
	# _on_skill_selected fires from focus_on's signal, updating the detail panel.

func _refresh_detail() -> void:
	var sid: String = tree_view.selected_id()
	if sid == "" or not SkillsDB.SKILLS.has(sid):
		d_name.text = "—"; d_desc.text = ""; d_cost.text = ""; d_status.text = ""
		d_buy.disabled = true
		if _d_toggle: _d_toggle.visible = false
		if _d_toggle_hint: _d_toggle_hint.visible = false
		if _d_trial_btn: _d_trial_btn.visible = false
		return
	var d = SkillsDB.SKILLS[sid]
	var cost := SkillsDB.compute_cost(sid)
	d_name.text = d["name"]
	d_desc.text = d["desc"]
	d_cost.text = "Cost: %d ★" % cost
	d_branch.text = "Branch: " + SkillsDB.BRANCH_NAMES.get(d["branch"], d["branch"])

	var unlock_all: bool = Global.debug_toggles.get("unlock_all", false)
	var purchased := SkillsDB.is_purchased(sid) or unlock_all
	var prereq := SkillsDB.prereqs_met(sid) or unlock_all
	var affordable := SkillsDB.can_afford(sid) or unlock_all
	# Only the "can't afford it yet" branch offers the ad trial, so default off
	# and let that one branch opt back in.
	if _d_trial_btn: _d_trial_btn.visible = false

	if purchased:
		d_status.text = "OWNED"
		d_status.modulate = Color(0.30, 0.70, 0.30)
		d_buy.text = "Owned"
		d_buy.disabled = true
		# Show active toggle for purchased skills — but not for load-bearing
		# ones like basic UI, HUD, procgen and basic enemies. Disabling those
		# leaves the game visibly broken, so we hide the toggle entirely.
		var toggleable := SkillsDB.is_toggleable(sid)
		if _d_toggle:
			var fkey = SkillsDB.get_feature_key(sid)
			_d_toggle.visible = toggleable
			_d_toggle.set_block_signals(true)
			_d_toggle.button_pressed = bool(Global.feature_overrides.get(fkey, true))
			_d_toggle.set_block_signals(false)
		if _d_toggle_hint:
			_d_toggle_hint.visible = toggleable
			if not toggleable:
				# Explain WHY the toggle is missing so it doesn't feel like a bug.
				pass
	elif not prereq:
		var missing := []
		for r in d.get("requires", []):
			if not SkillsDB.is_purchased(r):
				missing.append(SkillsDB.SKILLS[r]["name"])
		d_status.text = "Locked\nNeeds: " + ", ".join(missing)
		d_status.modulate = Color(0.65, 0.30, 0.25)
		d_buy.text = "Locked"
		d_buy.disabled = true
		if _d_toggle: _d_toggle.visible = false
		if _d_toggle_hint: _d_toggle_hint.visible = false
	elif not affordable:
		var fkey_trial = SkillsDB.get_feature_key(sid)
		if Global.is_trial_unlock(fkey_trial):
			d_status.text = "On loan for your next run"
			d_status.modulate = Color(0.30, 0.55, 0.70)
		else:
			d_status.text = "Not enough tokens"
			d_status.modulate = Color(0.65, 0.45, 0.20)
		d_buy.text = "Need %d ★" % cost
		d_buy.disabled = true
		if _d_toggle: _d_toggle.visible = false
		if _d_toggle_hint: _d_toggle_hint.visible = false
		# Offer a one-run taste of what they're saving up for. Genuinely
		# additive: the ad hands over the feature instead of interrupting.
		if _d_trial_btn:
			_d_trial_btn.visible = IAP.ads_enabled() and not Global.is_trial_unlock(fkey_trial)
	else:
		d_status.text = "Available"
		d_status.modulate = Color(0.18, 0.14, 0.10)
		d_buy.text = "Buy (%d ★)" % cost
		d_buy.disabled = false
		if _d_toggle: _d_toggle.visible = false
		if _d_toggle_hint: _d_toggle_hint.visible = false
		
		# Jiggle tween to draw attention — but not while a guide owns the screen.
		# The finger is already pointing at whatever the player should press, and a
		# second thing waving for a tap just muddies that.
		if Onboarding.suppresses_juice():
			d_buy.rotation = 0.0
			return
		d_buy.pivot_offset = d_buy.size * 0.5
		var tw = create_tween()
		tw.tween_property(d_buy, "rotation", 0.1, 0.05)
		tw.tween_property(d_buy, "rotation", -0.1, 0.05)
		tw.tween_property(d_buy, "rotation", 0.05, 0.05)
		tw.tween_property(d_buy, "rotation", -0.05, 0.05)
		tw.tween_property(d_buy, "rotation", 0.0, 0.05)

## Store entry. Opens the in-game store (store_view.gd) rather than
## RevenueCat's native paywall, which didn't match the rest of the game.
func _on_store() -> void:
	var store := StoreView.open(self)
	store.closed.connect(_refresh)

## Rewarded-ad trial for the selected skill. Nothing is granted until the ad
## actually reports completion — never on the button press.
func _on_trial() -> void:
	var sid: String = tree_view.selected_id()
	if sid == "": return
	if not IAP.ads_enabled():
		_flash_title("No ad available right now")
		return
	_d_trial_btn.disabled = true
	var fkey = SkillsDB.get_feature_key(sid)
	var earned: bool = await IAP.show_rewarded(IAP.PLACEMENT_SKILL_TRIAL)
	# The scene can be gone by the time a real ad returns.
	if not is_instance_valid(self) or not is_inside_tree(): return
	if not earned:
		AudioManager.play("ui_glass", -4.0, 0.05)
		_d_trial_btn.disabled = false
		_flash_title("No ad available right now")
		return
	Global.grant_trial_unlock(fkey)
	AudioManager.play("ui_buy", 0.0, 0.04)
	_d_trial_btn.disabled = false
	# _refresh() rewrites the title, so it has to land before the flash message.
	_refresh()
	_flash_title("%s is yours for one run!" % SkillsDB.SKILLS[sid]["name"])

## Borrow the title label for a transient message, then put it back. The shop
## has no toast widget and this screen is too busy to earn one.
func _flash_title(msg: String) -> void:
	title_label.text = msg
	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(title_label):
		title_label.text = "Skill Tree"

func _on_toggle_active(pressed: bool) -> void:
	var sid: String = tree_view.selected_id()
	if sid == "": return
	var unlock_all: bool = Global.debug_toggles.get("unlock_all", false)
	if not SkillsDB.is_purchased(sid) and not unlock_all: return
	var fkey = SkillsDB.get_feature_key(sid)
	Global.set_feature_override(fkey, pressed)
	# The chosen font follows the Font Select switch live, so the info panel
	# drops back to the plain font the moment it's turned off.
	if fkey == "font_select":
		UITheme.apply_font_choice(self)
	tree_view.queue_redraw()

func _on_skill_selected(_sid: String) -> void:
	_refresh_detail()

func _on_buy() -> void:
	var sid: String = tree_view.selected_id()
	if sid == "": return
	if SkillsDB.purchase(sid):
		AudioManager.play("ui_buy", 0.0, 0.04)
		Onboarding.notify_purchase(sid)
		if SkillsDB.get_feature_key(sid) == "font_select":
			UITheme.apply_font_choice(self)
		# small celebration tween on token label
		var tw = create_tween()
		tw.tween_property(tokens_label, "scale", Vector2(1.25, 1.25), 0.10).set_trans(Tween.TRANS_BACK)
		tw.tween_property(tokens_label, "scale", Vector2.ONE, 0.18)
	else:
		AudioManager.play("ui_glass", -4.0, 0.05)
	_refresh()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")
