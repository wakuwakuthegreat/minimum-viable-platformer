extends Node
## Onboarding — the forced first-run guide. Walks a brand-new player from their
## second death through buying UI → Procgen → Basic Enemies, using story_cut.gd
## for the patter and guide_finger.gd for the pointing.
##
## The sequence crosses three scenes (level → main menu → shop), so its position
## lives in Global.onboard_step and is saved — killing the app mid-tutorial
## resumes where it left off.
##
## Each scene calls Onboarding.attach(self, "<context>") from _ready():
##   ui.gd        → "game_over"
##   main_menu.gd → "main_menu"
##   shop.gd      → "shop"
##
## Any step whose target is already bought, missing, unrevealed or unaffordable
## silently advances instead of pointing at nothing.

const STEP_BUY_UI  := "buy_ui"
const STEP_MENU    := "menu_shop"
const STEP_PROCGEN := "shop_procgen"
const STEP_ENEMIES := "shop_enemies"
const STEP_DONE    := "done"

## Skills the guide walks the player through, in order. Global reads this to
## guarantee the player can afford the whole chain.
const CHAIN := ["ui", "procgen", "enemies_basic"]

## ─── PHASE 2 ────────────────────────────────────────────────────────────
## A second, softer guide. Once the player is sitting on a pile of tokens and
## still hasn't bought the polish upgrades, a death arms it and the finger comes
## back to walk them to the shop. Unlike phase 1 it owns no saved step: progress
## is simply "which of these is still unbought", so it can't desync.
##
## Prerequisites are walked first (you cannot point at a locked node), so the
## real order is the dependency closure of these three.
const CHAIN2 := ["juice_squash", "player_sprite", "main_menu_extras"]
## Tokens on hand at death before the second guide will arm.
const PHASE2_TOKEN_GATE := 25

## ─── PHASE 3 ────────────────────────────────────────────────────────────
## The enemy guide. A player who keeps running the same easy level instead of
## visiting the shop, while already able to afford the harder (better-paying)
## enemies and their sprite art, gets walked there. Same shape as phase 2:
## armed by a death, progress is "what's still unbought", disarms when done.
const CHAIN3 := ["enemies_advanced", "enemy_sprites"]
## Deaths in a row without opening the shop before phase 3 will arm.
const PHASE3_RUNS_WITHOUT_SHOP := 3

## Per late guide: its chain, the saved armed flag in Global, and its two cuts.
const LATE_GUIDES := {
	"p3": {"chain": CHAIN3, "flag": "onboard3_armed",
		"cut_intro": "guide3_intro", "cut_shop": "guide3_shop"},
	"p2": {"chain": CHAIN2, "flag": "onboard2_armed",
		"cut_intro": "guide2_intro", "cut_shop": "guide2_shop"},
}

const StoryCut := preload("res://story_cut.gd")
const GuideFinger := preload("res://guide_finger.gd")

var _finger: Node = null
var _cut_busy: bool = false
var _running: bool = false
var _pending_sid: String = ""
var _shop_host: Node = null
## True while the currently-attached guide is a late guide (phase 2 or 3).
var _phase2: bool = false
## Which late guide is attached: a key of LATE_GUIDES, or "".
var _late: String = ""

func step() -> String:
	var s := String(Global.onboard_step)
	return s if s != "" else STEP_BUY_UI

## Global reads this to floor the token balance while the guide is running.
func chain() -> Array:
	return CHAIN

func is_done() -> bool:
	return step() == STEP_DONE

## ─── PHASE 2 STATE ──────────────────────────────────────────────────────

## The dependency closure of a late guide's chain, in an order where every
## entry's prereqs come before it. Anything already owned drops out, so an empty
## result means the whole chain is bought and that guide has nothing left to say.
func late_targets(g: String) -> Array:
	var out: Array = []
	for sid in LATE_GUIDES[g]["chain"]:
		_collect_unbought(sid, out)
	return out

func _collect_unbought(sid: String, out: Array) -> void:
	if sid in out: return
	if not SkillsDB.SKILLS.has(sid): return
	if SkillsDB.is_purchased(sid): return
	for req in SkillsDB.SKILLS[sid].get("requires", []):
		_collect_unbought(String(req), out)
	out.append(sid)

## The next node a late guide should point at, or "" when it's finished.
func late_next(g: String) -> String:
	var t := late_targets(g)
	return String(t[0]) if not t.is_empty() else ""

func late_armed(g: String) -> bool:
	return bool(Global.get(LATE_GUIDES[g]["flag"])) and not late_targets(g).is_empty()

## Whether a late guide's next target can actually be bought right now. The late
## guides point at Shop from two screens that can't see the tree, and the finger
## gates every other button — so if the shop has nothing buyable, pointing there
## would trap the player in a menu → shop → menu loop with no way to start a run.
## In that case the guide stays armed but silent, and picks up again once they
## can afford it.
func late_ready(g: String) -> bool:
	if not late_armed(g): return false
	var sid := late_next(g)
	if sid == "": return false
	return SkillsDB.SKILLS.has(sid) and not SkillsDB.is_purchased(sid) 		and SkillsDB.prereqs_met(sid) and SkillsDB.can_afford(sid)

## The late guide that should run on this screen, or "". Phase 3 goes first:
## it only arms after the player has been dodging the shop, so it is the more
## pressing of the two.
func active_late_guide() -> String:
	for g in LATE_GUIDES:
		if late_ready(g): return g
	return ""

## True when either late guide has something it can point at right now.
func any_late_ready() -> bool:
	return active_late_guide() != ""

## Kept for callers that only know about the polish guide.
func phase2_targets() -> Array: return late_targets("p2")
func phase2_next() -> String: return late_next("p2")
func phase2_armed() -> bool: return late_armed("p2")
func phase2_ready() -> bool: return late_ready("p2")

## Called from the death path once the player is rich enough. Returns true if the
## guide actually armed — if every polish upgrade is already owned it arms
## nothing and no finger will ever appear.
func arm_phase2() -> bool:
	if not is_done(): return false          # phase 1 still has the floor
	if Global.onboard2_armed: return true
	if Global.tokens < PHASE2_TOKEN_GATE: return false
	if phase2_targets().is_empty(): return false
	Global.onboard2_armed = true
	Global.save_state()
	return true

## Called from the death path. Arms the enemy guide when the player has died
## PHASE3_RUNS_WITHOUT_SHOP times without opening the shop and can afford every
## enemy upgrade still missing from CHAIN3 (prereqs included).
func arm_phase3() -> bool:
	if not is_done(): return false
	if Global.onboard3_armed: return true
	if Global.runs_since_shop < PHASE3_RUNS_WITHOUT_SHOP: return false
	var targets := late_targets("p3")
	if targets.is_empty(): return false
	var total := 0
	for sid in targets:
		total += SkillsDB.compute_cost(sid)
	if Global.tokens < total: return false
	Global.onboard3_armed = true
	Global.save_state()
	return true

func _disarm_late_if_complete() -> void:
	for g in LATE_GUIDES:
		var flag: String = LATE_GUIDES[g]["flag"]
		if bool(Global.get(flag)) and late_targets(g).is_empty():
			Global.set(flag, false)
			Global.save_state()

## ─── JUICE SUPPRESSION ──────────────────────────────────────────────────

## Menus ask this before playing their attention-grabbing wiggle on a button.
## Three cases, all the same rule — the guide owns the player's attention:
##   • the first guide hasn't been completed yet, so no death-menu button should
##     be jiggling for a player who is about to be pointed somewhere specific;
##   • a guide (either phase) is on screen right now;
##   • the polish guide is armed AND has something buyable, so its finger is
##     about to arrive. (Armed-but-broke doesn't count — no finger comes, so the
##     usual juice should play.)
func suppresses_juice() -> bool:
	return (not is_done()) or is_active() or any_late_ready()

## True while a cut or the finger owns the screen — StoryDB checks this so
## ambient story scenes never talk over the guide.
## True while a step is mid-flight (cut playing, tree panning) or the finger owns
## the screen — StoryDB checks this so ambient scenes never talk over the guide.
func is_active() -> bool:
	return _running or _cut_busy or (_finger != null and is_instance_valid(_finger))

func set_step(s: String) -> void:
	if Global.onboard_step == s: return
	Global.onboard_step = s
	Global.save_state()

## Called by ui.gd the moment UI is bought, before it changes scene.
func advance_to(s: String) -> void:
	_clear_finger()
	set_step(s)

## Called by shop.gd:_on_buy() after a successful purchase.
func notify_purchase(sid: String) -> void:
	if sid == "" or sid != _pending_sid: return
	_pending_sid = ""
	_clear_finger()
	if _phase2:
		_disarm_late_if_complete()
		if any_late_ready() and _shop_host != null and is_instance_valid(_shop_host):
			await get_tree().create_timer(0.9).timeout
			if is_instance_valid(_shop_host):
				attach(_shop_host, "shop")
		return
	if sid == "procgen":
		set_step(STEP_ENEMIES)
	elif sid == "enemies_basic":
		set_step(STEP_DONE)
	if step() != STEP_DONE and _shop_host != null and is_instance_valid(_shop_host):
		await get_tree().create_timer(0.9).timeout
		if is_instance_valid(_shop_host):
			attach(_shop_host, "shop")

func attach(host: Node, context: String) -> void:
	_clear_finger()
	if host == null: return
	if is_done():
		# Phase 1 finished. A late guide (enemies, then polish) takes over only
		# once a death has armed it and it has something buyable to point at.
		_disarm_late_if_complete()
		_late = active_late_guide()
		if _late == "": return
		_phase2 = true
		_running = true
		match context:
			"game_over", "game_over_pre_ui": await _run2_game_over(host)
			"main_menu":                     await _run2_menu(host)
			"shop":                          await _run2_shop(host)
		_running = false
		return
	_phase2 = false
	# Set synchronously, before the first await below, so a same-frame deferred
	# _play_pending_cut() in the host sees is_active() and stands down.
	_running = true
	match context:
		"game_over", "game_over_pre_ui": await _run_buy_ui(host)
		"main_menu":                     await _run_menu(host)
		"shop":                          await _run_shop(host)
	_running = false


## ─── PHASE 2 STEPS ──────────────────────────────────────────────────────
## Same shape as phase 1, but every step is derived from what's still unbought
## rather than from a saved cursor, and the game-over screen points at Shop
## instead of at Retry.

func _run2_game_over(host: Node) -> void:
	if not late_ready(_late): return
	await _play_cut(LATE_GUIDES[_late]["cut_intro"])
	if not is_instance_valid(host): return
	var btn: Button = host.get("btn_shop")
	if not _button_ok(btn):
		# No shop button on this game-over card (pre-UI layout) — stay armed and
		# catch the player on the menu instead.
		return
	_ensure_finger().point_at_control(btn)

func _run2_menu(host: Node) -> void:
	if not late_ready(_late): return
	if not is_instance_valid(host): return
	var btn: Button = host.get("shop_btn")
	if not _button_ok(btn):
		push_warning("[Onboarding] Shop button unavailable — no finger shown.")
		return
	_ensure_finger().point_at_control(btn)

func _run2_shop(host: Node) -> void:
	_shop_host = host
	var sid := late_next(_late)
	if sid == "":
		_disarm_late_if_complete()
		return

	var tv: Control = host.get("tree_view")
	if not _skill_ok(sid, tv):
		# Unaffordable or not yet revealed: let the player play. The guide stays
		# armed and re-points next time they walk in with more tokens.
		return

	await _play_cut(LATE_GUIDES[_late]["cut_shop"])
	if not is_instance_valid(host) or not is_instance_valid(tv): return

	tv.focus_on(sid)
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(host) or not is_instance_valid(tv): return
	if not _skill_ok(sid, tv):
		return

	_pending_sid = sid
	var r: float = tv.node_screen_radius()
	var centre: Vector2 = tv.screen_pos_of(sid)
	_ensure_finger().point_at_rect(Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0))

	var cb := Callable(self, "_on_shop_node_selected").bind(host)
	if not tv.skill_selected.is_connected(cb):
		tv.skill_selected.connect(cb)


## ─── STEPS ──────────────────────────────────────────────────────────────

func _run_buy_ui(host: Node) -> void:
	if Global.is_unlocked("ui"):
		set_step(STEP_MENU)
		return
	set_step(STEP_BUY_UI)
	await _play_cut("guide_buy_ui")
	if not is_instance_valid(host): return
	var btn: Button = host.get("btn_buy_ui")
	if not _button_ok(btn):
		push_warning("[Onboarding] Buy UI button unavailable — no finger shown.")
		return
	_ensure_finger().point_at_control(btn)

func _run_menu(host: Node) -> void:
	# Reached whenever the player is on the menu with shop steps outstanding —
	# including after bailing out of the shop, so the guide can re-point.
	if step() == STEP_BUY_UI:
		set_step(STEP_MENU)
	await _play_cut("guide_menu")
	if not is_instance_valid(host): return
	var btn: Button = host.get("shop_btn")
	if not _button_ok(btn):
		push_warning("[Onboarding] Shop button unavailable — no finger shown.")
		set_step(STEP_PROCGEN)
		return
	if step() == STEP_MENU:
		set_step(STEP_PROCGEN)
	_ensure_finger().point_at_control(btn)

func _run_shop(host: Node) -> void:
	_shop_host = host
	var sid := ""
	var cut_id := ""
	match step():
		STEP_BUY_UI, STEP_MENU, STEP_PROCGEN:
			sid = "procgen"; cut_id = "guide_procgen"
			set_step(STEP_PROCGEN)
		STEP_ENEMIES:
			sid = "enemies_basic"; cut_id = "guide_enemies"
		_:
			return

	var tv: Control = host.get("tree_view")
	if not _skill_ok(sid, tv):
		_skip_skill(sid)
		return

	await _play_cut("guide_shop_intro")
	if not is_instance_valid(host): return
	await _play_cut(cut_id)
	if not is_instance_valid(host) or not is_instance_valid(tv): return

	# Pan/zoom the tree so the node is on screen, then let the pan settle before
	# the finger lands on it. focus_on also selects it, so the Buy button is live.
	tv.focus_on(sid)
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(host) or not is_instance_valid(tv): return
	if not _skill_ok(sid, tv):
		_skip_skill(sid)
		return

	_pending_sid = sid
	var r: float = tv.node_screen_radius()
	var centre: Vector2 = tv.screen_pos_of(sid)
	_ensure_finger().point_at_rect(Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0))

	# Tapping the node re-emits skill_selected; that's the cue to move the finger
	# onto Buy. Connected after focus_on so its own emission doesn't skip a beat.
	var cb := Callable(self, "_on_shop_node_selected").bind(host)
	if not tv.skill_selected.is_connected(cb):
		tv.skill_selected.connect(cb)

func _on_shop_node_selected(selected: String, host: Node) -> void:
	if _pending_sid == "" or selected != _pending_sid: return
	if _finger == null or not is_instance_valid(_finger): return
	if not is_instance_valid(host): return
	var buy: Button = host.get("d_buy")
	if not _button_ok(buy):
		return
	_finger.point_at_control(buy)


## ─── GUARDS ─────────────────────────────────────────────────────────────

func _button_ok(b) -> bool:
	return b != null and is_instance_valid(b) and b.visible and not b.disabled

## The user's rule: if the node isn't there to be bought, that's a bug — skip it
## rather than point the finger at nothing and lock the screen.
func _skill_ok(sid: String, tv: Control) -> bool:
	if not SkillsDB.SKILLS.has(sid):
		push_warning("[Onboarding] '%s' is not in SkillsDB.SKILLS — skipping." % sid)
		return false
	if SkillsDB.is_purchased(sid):
		return false
	if not SkillsDB.prereqs_met(sid):
		push_warning("[Onboarding] '%s' prereqs unmet — skipping." % sid)
		return false
	if not SkillsDB.can_afford(sid):
		push_warning("[Onboarding] '%s' unaffordable — skipping." % sid)
		return false
	if tv != null and is_instance_valid(tv) and tv.has_method("is_revealed"):
		if not tv.is_revealed(sid):
			push_warning("[Onboarding] '%s' not revealed in the tree — skipping." % sid)
			return false
	return true

func _skip_skill(sid: String) -> void:
	_pending_sid = ""
	if sid == "procgen":
		set_step(STEP_ENEMIES)
		if _shop_host != null and is_instance_valid(_shop_host):
			_run_shop(_shop_host)
	elif sid == "enemies_basic":
		set_step(STEP_DONE)


## ─── PLUMBING ───────────────────────────────────────────────────────────

func _play_cut(scene_id: String) -> void:
	if StoryDB.is_seen(scene_id): return
	var scene: Dictionary = StoryDB.scene_by_id(scene_id)
	if scene.is_empty(): return
	_cut_busy = true
	var cut = StoryCut.new()
	get_tree().root.add_child(cut)
	cut.play(scene.get("blocks", []), String(scene.get("mode", "scrim")))
	StoryDB.mark_seen(scene)
	await cut.finished
	_cut_busy = false

func _ensure_finger() -> Node:
	if _finger != null and is_instance_valid(_finger):
		return _finger
	_finger = GuideFinger.new()
	# Added last under root so its _input runs before the scene's — that is what
	# makes "only the target is tappable" work without a blocker rect.
	get_tree().root.add_child(_finger)
	return _finger

func _clear_finger() -> void:
	if _finger != null and is_instance_valid(_finger):
		_finger.queue_free()
	_finger = null

