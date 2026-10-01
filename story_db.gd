extends Node
## StoryDB — every spoken line in the game plus the rules for when it fires.
##
## ╔═══════════════════════════════════════════════════════════════════════╗
## ║  ADDING DIALOG                                                        ║
## ║  1. Append one dict to SCENES (below). That's it.                     ║
## ║  2. New character? Append one dict to VOICES and use its key as `who`. ║
## ╚═══════════════════════════════════════════════════════════════════════╝
##
## A scene looks like this:
##
##   {
##     "id": "death_3",                 # unique; remembered in Global.story_seen
##     "at": "death",                   # death | menu_open | shop_open | run_start
##     "when": {"deaths_at": [3]},      # all keys must pass (see _matches below)
##     "mode": "black",                 # black = full lore cut, scrim = over live scene
##     "blocks": [                      # one tap per block
##       {"who": "narrator", "text": "Three deaths. You are improving."},
##       {"who": "soul",     "text": "he counts wrong on purpose"},
##     ],
##   }
##
## Condition keys understood by "when" (every key is optional, all are AND-ed):
##   deaths_at: [3, 5]            exact death counts
##   deaths_at_least: 10          death count floor
##   distance_at_least: 400       metres reached in the run that just ended
##   best_at_least: 900           best distance ever
##   purchased: "procgen"         that skill is owned (fires the next trigger)
##   not_purchased: "coins"       that skill is NOT owned
##   requires_unlocked: "ui"      feature key is unlocked
##   not_unlocked: "ui"           feature key is not unlocked
##   days_away_at_least: 2.0      real days since the previous session
##   unspent_tokens_at_least: 15  hoarding check
##
## Extra scene keys: "once" (default true), "priority" (higher wins ties).

const FONT_TERMINUS := preload("res://assets/fonts/Terminus.ttf")
const FONT_KA1      := preload("res://assets/fonts/ka1.ttf")
const FONT_JUICE    := preload("res://assets/fonts/orange juice 2.0.ttf")
const FONT_NERVOUS  := preload("res://assets/fonts/Nervous.ttf")
const FONT_NASA     := preload("res://assets/fonts/nasalization-rg.ttf")

## ─── THE CAST ───────────────────────────────────────────────────────────
## fx_open/fx_close are BBCode — story_cut.gd renders bodies in a
## RichTextLabel, so [shake]/[wave]/[pulse] work out of the box.
const VOICES := {
	"narrator": {
		"name": "NARRATOR", "font": FONT_TERMINUS, "size": 30,
		"color": Color(0.87, 0.86, 0.83),
		"fx_open": "", "fx_close": "",
		"speed": 0.032, "tick_db": -10.0,
	},
	"purple": {
		"name": "???", "font": FONT_KA1, "size": 42,
		"color": Color(0.60, 0.15, 0.90),
		"fx_open": "[shake rate=18.0 level=6]", "fx_close": "[/shake]",
		"speed": 0.055, "tick_db": -4.0, "upper": true, "glitch": true,
	},
	"princess": {
		"name": "THE PINK ONE", "font": FONT_JUICE, "size": 40,
		"color": Color(1.00, 0.56, 0.82),
		"fx_open": "[wave amp=22.0 freq=4.0]", "fx_close": "[/wave]",
		"speed": 0.030, "tick_db": -13.0,
	},
	"soul": {
		"name": "· · ·", "font": FONT_NERVOUS, "size": 26,
		"color": Color(0.44, 0.85, 0.82),
		"fx_open": "[pulse freq=1.0 color=#6fd9d055]", "fx_close": "[/pulse]",
		"speed": 0.070, "tick_db": -17.0, "lower": true,
	},
	"sponsor": {
		"name": "A WORD FROM OUR SPONSOR", "font": FONT_NASA, "size": 25,
		"color": Color(0.31, 0.88, 1.00),
		"fx_open": "", "fx_close": "",
		"speed": 0.024, "tick_db": -9.0, "upper": true,
	},
	"system": {
		"name": "", "font": FONT_TERMINUS, "size": 19,
		"color": Color(0.42, 0.42, 0.47),
		"fx_open": "", "fx_close": "",
		# [lb] is the BBCode escape for a literal "[" — a bare one would be
		# parsed as an (unknown) tag and swallowed.
		"speed": 0.010, "tick_db": -20.0, "prefix": "[lb] ", "suffix": " ]",
	},
}

func voice(who: String) -> Dictionary:
	return VOICES.get(who, VOICES["narrator"])


## ─── SCENES ─────────────────────────────────────────────────────────────
## `at: "guide"` scenes never auto-fire; onboarding.gd requests them by id.
const SCENES: Array = [

# ══ INTRO COLD OPEN ═══════════════════════════════════════════════════════
{
	"id": "intro_cold_open", "at": "guide", "mode": "black",
	"blocks": [
		{"who": "sponsor",  "text": "Welcome to your new platformer! Fully featured. Feature-complete. Complete with features."},
		{"who": "sponsor",  "text": "Please enjoy responsibly. Terms apply. Terms are not available."},
		{"who": "princess", "text": "oh! oh, a new one! hello! nobody tell it what happened to the last one"},
		{"who": "narrator", "text": "Nothing happened to the last one."},
		{"who": "soul",     "text": "something happened to the last one"},
		{"who": "narrator", "text": "Ignore that. It leaks in through the save file. Harmless."},
	],
},

# ══ GUIDED ONBOARDING ═════════════════════════════════════════════════════
{
	"id": "guide_buy_ui", "at": "guide", "mode": "scrim",
	"blocks": [
		{"who": "narrator", "text": "Right. It took the game and left you the physics. Generous, technically."},
		{"who": "narrator", "text": "You died, so you were paid. The further you go the more you get."},
		# DROPPED — uncomment to restore narrator closer:
		# {"who": "narrator", "text": "You can, actually. It kept the receipts. Start with the interface — you'll want menus before you want anything nice."},
	],
},
{
	"id": "guide_menu", "at": "guide", "mode": "scrim",
	"blocks": [
		{"who": "narrator", "text": "Congratulations. You now own a menu. Some people own houses."},
	],
},
{
	"id": "guide_shop_intro", "at": "guide", "mode": "scrim",
	"blocks": [
		{"who": "narrator", "text": "This is the tree. Every branch is something that improves the game."},
	],
},
{
	"id": "guide_procgen", "at": "guide", "mode": "scrim",
	"blocks": [
		{"who": "narrator", "text": "Right now there is one level. One. You have already seen all of it, and it has seen all of you."},
		{"who": "narrator", "text": "Buy the level generator first to fix that."},
	],
},
{
	"id": "guide_enemies", "at": "guide", "mode": "scrim",
	"blocks": [
		{"who": "narrator", "text": "Now buy the enemies. Yes, on purpose. Yes, they kill you."},
		{"who": "narrator", "text": "Every tier of enemy in the world pays more per tokens. The danger is the interest rate."},
		{"who": "purple",   "text": "They work for me."},
		{"who": "narrator", "text": "They work for the payout multiplier. So do you. Tap the node."},
	],
},

# ══ DEATH-COUNT MILESTONES ════════════════════════════════════════════════
{
	"id": "death_3", "at": "death", "mode": "black",
	"when": {"deaths_at": [3]},
	"blocks": [
		{"who": "narrator", "text": "Three deaths. Statistically, that is a trend."},
		# DROPPED — uncomment to restore:
		# {"who": "princess", "text": "or a HOBBY! some people collect stamps"},
	],
},
{
	"id": "death_5", "at": "death", "mode": "black",
	"when": {"deaths_at": [5]},
	"blocks": [
		{"who":"princess", "text": "HELLO! I'm the PRINCESS! Every good platformer needs one, apparently.
  "},
		{"who": "princess", "text": "...You're not here to rescue me, are you? You keep getting unalived."},
		# DROPPED — uncomment to restore:
		# {"who":	 "narrator", "text": "I do not replay them. I file them. There is a difference and it is my whole personality."},
	],
},
{
	"id": "death_7", "at": "death", "mode": "black",
	"when": {"deaths_at": [7]},
	"blocks": [
		{"who": "narrator", "text": "Seven. Lucky number. Not here. Here it is just seven."},
		# DROPPED — uncomment to restore full exchange:
		# {"who": "soul",     "text": "he told the last one it was lucky"},
		# {"who": "narrator", "text": "The last one had different circumstances."},
		# {"who": "soul",     "text": "the last one had the same circumstances"},
	],
},
{
	"id": "death_10", "at": "death", "mode": "black",
	"when": {"deaths_at": [10]},
	"blocks": [
		{"who": "sponsor",  "text": "TEN DEATHS! You have unlocked: nothing. But you have unlocked it TEN TIMES."},
		# DROPPED — uncomment to restore:
		# {"who": "narrator", "text": "Round numbers bring it out. Like a fly to a window."},
		# {"who": "princess", "text": "double digits!! i baked something. i can't give it to you. i can't reach"},
	],
},
{
	"id": "death_15", "at": "death", "mode": "black",
	"when": {"deaths_at": [15]},
	"blocks": [
		{"who": "narrator",   "text": "Fifteen. You're getting the hang of this!."}
	],
},
{
	"id": "death_21", "at": "death", "mode": "black",
	"when": {"deaths_at": [21]},
	"blocks": [
		{"who": "narrator", "text": "Twenty-one. You are legally an adult in this game."},
		{"who": "princess", "text": "he's so proud of that one. he's been saving it since eleven"}
	],
},
{
	"id": "death_30", "at": "death", "mode": "black",
	"when": {"deaths_at": [30]},
	"blocks": [
		{"who": "narrator", "text": "Thirty. At this point the deaths are the content and the running is the loading screen."},
		# DROPPED — uncomment to restore full exchange:
		{"who": "soul",     "text": "he says that to everyone. he said it to me. i believed it"},
		{"who": "narrator",   "text": "Quiet."},
		{"who": "system",   "text": "one voice removed from the transcript"},
	],
},
{
	"id": "death_50", "at": "death", "mode": "black",
	"when": {"deaths_at": [50]},
	"blocks": [
		{"who": "purple",   "text": "Fifty. I have never had to work this little."},
		{"who": "narrator", "text": "Fifty deaths is, and I want to be precise, a lot of deaths."},
	],
},
{
	"id": "death_100", "at": "death", "mode": "black",
	"when": {"deaths_at": [100]},
	"blocks": [
		{"who": "narrator", "text": "A hundred. I would like to say something cutting here. I have run out."},
	],
},

# ══ DISTANCE MILESTONES ═══════════════════════════════════════════════════
{
	"id": "dist_250", "at": "death", "mode": "black",
	"when": {"distance_at_least": 250},
	"blocks": [
		{"who": "narrator", "text": "You got some distance in. The far parts are less finished. Try not to look directly at them."},
	],
},
{
	"id": "dist_600", "at": "death", "mode": "black",
	"when": {"distance_at_least": 600},
	"blocks": [
		{"who": "princess", "text": "you went PAST the bit i live in! nobody goes past the bit i live in"},
		# DROPPED — uncomment to restore full exchange:
		# {"who": "narrator", "text": "There is no bit it lives in. It is a text style."},
		# {"who": "princess", "text": "rude. accurate. rude"},
	],
},
{
	"id": "dist_1200", "at": "death", "mode": "black",
	"when": {"distance_at_least": 1200},
	"blocks": [
		{"who": "soul",     "text": "keep going. there's an edge. i'd like someone to see it"},
		# DROPPED — uncomment to restore:
		# {"who": "purple",   "text": "Far. Too far. I did not build past here."},
		# {"who": "narrator", "text": "It did not build any of it. It found it. Like a hermit crab with opinions."},
	],
},

# ══ NEW DEATH MILESTONES ══════════════════════════════════════════════════



{
	"id": "death_18", "at": "death", "mode": "black",
	"when": {"deaths_at": [18]},
	"blocks": [
		{"who": "princess", "text": "eighteen! vote for your favorite hazard!"},
		{"who": "narrator", "text": "The voting booth was removed for budget reasons. The spikes won anyway."},
	],
},


{
	"id": "death_42", "at": "death", "mode": "black",
	"when": {"deaths_at": [42]},
	"blocks": [
		{"who": "narrator", "text": "Deep Thought did not account for your reaction time."},
	],
},


{
	"id": "death_75", "at": "death", "mode": "black",
	"when": {"deaths_at": [75]},
	"blocks": [
		 {"who": "princess", "text": "75!! three quarters of a hundred!!"},
		 {"who": "narrator", "text": "Thank you for the arithmetic lesson, Pink One."},
	],
},

{
	"id": "death_120", "at": "death", "mode": "black",
	"when": {"deaths_at": [120]},
	"blocks": [
		{"who": "princess",  "text": "120 RUNS! You have officially spent more time dead than airborne!"},
	],
},
{
	"id": "death_150", "at": "death", "mode": "black",
	"when": {"deaths_at": [150]},
	"blocks": [
		 {"who": "purple",   "text": "150. Even I am starting to feel bad. Almost."},
		 {"who": "narrator", "text": "Don't lie to the player, it breaks immersion."},
	],
},

{
	"id": "death_300", "at": "death", "mode": "black",
	"when": {"deaths_at": [300]},
	"blocks": [
		{"who": "princess", "text": "THIS IS SPARTA! ...wait, no, this is death three hundred!"},
		{"who": "narrator", "text": "Please refrain from referencing outdated memes in my narrative log."},
	],
},
{
	"id": "death_404", "at": "death", "mode": "black",
	"when": {"deaths_at": [404]},
	"blocks": [
		{"who": "system",   "text": "error 404: winning_strategy not found"},
	],
},
{
	"id": "death_500", "at": "death", "mode": "black",
	"when": {"deaths_at": [500]},
	"blocks": [
		{"who": "narrator", "text": "Five hundred deaths. You have died more times than the dev team did during testing."},
		{"who": "purple",   "text": "And we tested it terribly."},
	],
},
{
	"id": "death_1000", "at": "death", "mode": "black",
	"when": {"deaths_at": [1000]},
	"blocks": [
		{"who": "narrator", "text": "One thousand deaths. I have no more commentary. You win by sheer stubbornness."},
		{"who": "princess", "text": "1,000!! HAPPY ONE THOUSANDTH DEATH!! I MADE VIRTUAL CONFETTI!!"},\
	],
},

# ══ KEY-SKILL PURCHASES ═══════════════════════════════════════════════════
{
	"id": "buy_procgen", "at": "shop_open", "mode": "black",
	"when": {"purchased": "procgen"},
	"blocks": [
		{"who": "narrator", "text": "Good, the shop was feeling lonely."},
	],
},
{
	"id": "buy_enemies", "at": "shop_open", "mode": "black",
	"when": {"purchased": "enemies_basic"},
	"blocks": [
		{"who": "purple",   "text": "You bought my staff back. With my money."},
		# DROPPED — uncomment to restore soul interjection:
		# {"who": "soul",     "text": "the loop isn't closed. i got out. this is out"},
	],
},
{
	"id": "buy_coins", "at": "shop_open", "mode": "black",
	"when": {"purchased": "coins"},
	"blocks": [
		{"who": "sponsor",  "text": "CURRENCY RESTORED! Shiny objects now spawn in the world. Collect them. Do not ask where they come from."},
		{"who": "narrator", "text": "They come from a spawn table. Everyone here is very dramatic about arrays."},
		# DROPPED — uncomment to restore:
		# {"who": "purple",   "text": "They come from me."},
	],
},
{
	"id": "buy_leaderboard", "at": "shop_open", "mode": "black",
	"when": {"purchased": "leaderboard"},
	"blocks": [
		{"who": "narrator", "text": "You bought the leaderboard. Now strangers can see exactly how you're doing."},
		 {"who": "princess", "text": "other people?? other people exist?? put me on it. put my name on it"},
	],
},

# ══ IDLE / RETURN / HOARDING ══════════════════════════════════════════════
{
	# Fires once, on the very next run, only for a player who backed all the
	# way out of the app (not just to a menu — there wasn't one yet) via
	# ui_back/ui_cancel. See pause_menu.gd and Global.early_quit_before_unlock.
	"id": "early_quit_scold", "at": "run_start", "mode": "scrim", "once": true,
	"priority": 5,
	"when": {"early_quit_pending": true},
	"blocks": [
		{"who": "narrator", "text": "You were so quick to leave. You never even unlocked anything yet. How cruel."},
	],
},
{
	"id": "return_gap", "at": "run_start", "mode": "black", "once": false,
	"when": {"days_away_at_least": 2.0},
	"blocks": [
		{"who": "narrator", "text": "Oh. You're back. No, it's fine. I kept everything exactly where you left it, because I can't move."},
	],
},
{
	"id": "hoard_tokens", "at": "shop_open", "mode": "scrim", "once": false,
	"when": {"unspent_tokens_at_least": 20},
	"blocks": [
		{"who": "narrator", "text": "That is a substantial pile of tokens you are not spending. No pressure. It's only the world."},
	],
},
{
	# Nudge toward the shop once there's real money on the table. Low priority so a
	# death-count milestone always wins the slot. Fires once, then the late version
	# re-arms much later so the player gets a second nudge after many more deaths.
	"id": "spend_reminder", "at": "death", "mode": "scrim", "once": true,
	"priority": -5,
	"when": {"unspent_tokens_at_least": 10, "requires_unlocked": "ui",
		"no_guide_pending": true},
	"blocks": [
		{"who": "narrator", "text": "You are carrying ten tokens that can onl be used for the shop... because you haven't been to the shop."},
	],
},
{
	"id": "spend_reminder_late", "at": "death", "mode": "scrim", "once": false,
	"priority": -5,
	"when": {"unspent_tokens_at_least": 10, "deaths_at_least": 30, "requires_unlocked": "ui",
		"no_guide_pending": true},
	"blocks": [
		{"who": "narrator", "text": "You are still carrying those tokens. The shop has been there the entire time. I can see it from here."},
	],
},

# ══ POLISH GUIDE (SECOND PASS) ════════════════════════════════════════════
# Requested by id from onboarding.gd's phase-2 runners, never auto-fired.
{
	"id": "guide2_intro", "at": "guide", "mode": "scrim",
	"blocks": [
		{"who": "narrator", "text": "You have money now. Quite a lot of it, for someone whose only income is dying."},
		# DROPPED — uncomment to restore purple interjection:
		# {"who": "purple",   "text": "It runs. It lands. It is not pleasant to look at."},
		{"who": "narrator", "text": "He means the game has no feel. Everything moves, nothing lands. Let's fix that part."},
		{"who": "narrator", "text": "Shop. I'll point."},
	],
},
{
	"id": "guide2_shop", "at": "guide", "mode": "scrim",
	"blocks": [
		{"who": "narrator", "text": "Squash and stretch, a sprite that isn't a rectangle, and a menu that isn't an apology."},
		{"who": "sponsor",  "text": "POLISH IS NOT COSMETIC! Polish is how the player knows the thing happened! That one is FREE ADVICE and I regret it!"},
		{"who": "narrator", "text": "It's right, irritatingly. Buy them in the order I point."},
	],
},
{
	"id": "guide3_intro", "at": "guide", "mode": "scrim",
	"blocks": [
		{"who": "narrator", "text": "Three runs in a row and not one look at the shop. I have been keeping count. It is my whole job."},
		{"who": "narrator", "text": "You can afford the nasty ones now. Bombs, drills, shooters — and art so you can see them coming."},
		{"who": "purple",   "text": "More teeth."},
		{"who": "narrator", "text": "More teeth, more tokens. Shop. I'll point."},
	],
},
{
	"id": "guide3_shop", "at": "guide", "mode": "scrim",
	"blocks": [
		{"who": "narrator", "text": "Harder enemies pay better. That is the entire economy, really."},
		{"who": "sponsor",  "text": "RISK IS JUST REWARD THAT HASN'T HAPPENED YET! Consult no one!"},
		{"who": "narrator", "text": "Buy them in the order I point."},
	],
},

]

## ─── MATCHING ───────────────────────────────────────────────────────────
## Scenes with once=true are remembered forever in Global.story_seen.
## Scenes with once=false fire at most once per app session.
var _session_seen: Dictionary = {}

func scene_by_id(id: String) -> Dictionary:
	for s in SCENES:
		if String(s.get("id", "")) == id:
			return s
	push_warning("[StoryDB] no scene with id '%s'" % id)
	return {}

## First unseen scene whose conditions pass for this trigger point, else {}.
## Trigger points: "death", "menu_open", "shop_open", "run_start".
func pending(at: String) -> Dictionary:
	# The guided onboarding owns the screen while it runs — never talk over it.
	var ob = get_node_or_null("/root/Onboarding")
	if ob and ob.has_method("is_active") and ob.is_active():
		return {}
	var best: Dictionary = {}
	var best_priority := -9999
	for s in SCENES:
		if String(s.get("at", "")) != at: continue
		if is_seen(String(s.get("id", ""))): continue
		if not _matches(s.get("when", {})): continue
		var p := int(s.get("priority", 0))
		if p > best_priority:
			best_priority = p
			best = s
	return best

func is_seen(id: String) -> bool:
	if id == "": return true
	if _session_seen.has(id): return true
	return bool(Global.story_seen.get(id, false))

func mark_seen(scene: Dictionary) -> void:
	var id := String(scene.get("id", ""))
	if id == "": return
	if id == "early_quit_scold":
		# One-shot flag, separate from story_seen — clear it now that the
		# line it exists for has actually played.
		Global.early_quit_before_unlock = false
	if bool(scene.get("once", true)):
		Global.story_seen[id] = true
		Global.save_state()
	else:
		_session_seen[id] = true

func _skills() -> Node:
	return get_node_or_null("/root/SkillsDB")

func _deaths() -> int:
	return int(Global.stats.get("deaths", 0))

func _purchased(sid: String) -> bool:
	var sk := _skills()
	if sk and sk.has_method("is_purchased"):
		return bool(sk.is_purchased(sid))
	return bool(Global.unlocked.get(sid, false))

## True when a guide is unfinished, or the polish guide is armed with something it
## can actually point at — i.e. the finger is about to speak on this very screen.
## Reminders stand down rather than double up.
func _guide_pending() -> bool:
	var ob = get_node_or_null("/root/Onboarding")
	if ob == null: return false
	if ob.has_method("is_done") and not ob.is_done(): return true
	if ob.has_method("any_late_ready") and ob.any_late_ready(): return true
	return false

func _matches(when: Dictionary) -> bool:
	for key in when.keys():
		var want = when[key]
		match key:
			"deaths_at":
				if not (_deaths() in want): return false
			"deaths_at_least":
				if _deaths() < int(want): return false
			"distance_at_least":
				if Global.last_run_distance < int(want): return false
			"best_at_least":
				if Global.best_distance < int(want): return false
			"purchased":
				if not _purchased(String(want)): return false
			"not_purchased":
				if _purchased(String(want)): return false
			"requires_unlocked":
				if not Global.is_unlocked(String(want)): return false
			"not_unlocked":
				if Global.is_unlocked(String(want)): return false
			"days_away_at_least":
				if Global.session_gap_days < float(want): return false
			"unspent_tokens_at_least":
				if Global.tokens < int(want): return false
			"no_guide_pending":
				if bool(want) and _guide_pending(): return false
			"early_quit_pending":
				if bool(want) and not Global.early_quit_before_unlock: return false
			_:
				push_warning("[StoryDB] unknown condition key '%s'" % key)
				return false
	return true


## ─── ONE-LINERS ─────────────────────────────────────────────────────────
## Short jabs for the game-over hint line. Not a scene — no tapping, no cut.
const TAUNTS: Array = [
	"The spikes were placed by a professional. Respect the craft.",
	"Gravity remains unpurchased. It works anyway. Enjoy the freebie.",
	"You were doing so well, in a sense, briefly.",
	"That was a decision. Not the one I'd have made, but a decision.",
	"Spend the tokens. Hoarding them is how the last one ended.",
	"Each death funds the world. You are its most reliable donor.",
	"Somewhere a leaderboard is quietly writing this down.",
	"The far parts of the level are unfinished. You will never know.",
	"I could tell you what killed you. It's in the name of the thing.",
	"Try going right. Right is where the tokens live.",
]

const FALL_TAUNTS: Array = [
	"Down is not a direction the design accounted for.",
	"You found the bottom. There is nothing there. That's the joke.",
	"The floor was optional and you opted out.",
]

## cause matches Global.last_death_cause (e.g. "fall", "spike", "enemy").
func taunt(cause: String = "", distance: int = 0, deaths: int = 0) -> String:
	var pool: Array = TAUNTS
	if cause.to_lower().contains("fall"):
		pool = FALL_TAUNTS + TAUNTS
	if deaths > 0 and deaths % 10 == 0:
		return "Death number %d. Round numbers deserve silence." % deaths
	if distance > 0 and distance >= Global.best_distance and Global.best_distance > 0:
		return "A personal best. The bar was on the floor and you cleared it."
	return pool[randi() % pool.size()]
