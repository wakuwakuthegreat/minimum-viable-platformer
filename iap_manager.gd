extends Node
## RevenueCat wrapper. Every purchase/entitlement/ad call in the game goes
## through here so that exactly one file knows whether the native SDK exists.
##
## The plugin (godotx_revenue_cat) ships as an Android .aar / iOS .xcframework
## reached through Engine.get_singleton("GodotxRevenueCat"). It is absent in the
## editor, in web exports and on desktop — so `available` is false there and
## every method below degrades to a no-op instead of crashing. The game must
## stay fully playable with no store attached; that is not a fallback, it is the
## normal case for most of development.
##
## SETUP STILL REQUIRED (see for_hackathon.md §3.1):
##   1. Drop addons/godotx_revenue_cat/ and android/revenuecat/ into the project.
##   2. Enable gradle build in the Android export preset.
##   3. Paste the public SDK keys into API_KEY_ANDROID / API_KEY_IOS below.
##   4. Create the products in Play Console and map them in the RevenueCat
##      dashboard using the PRODUCT_* ids below.

## ─── CONFIGURATION ──────────────────────────────────────────────────────

## Public RevenueCat SDK keys. These are *meant* to be shipped in the client —
## they are publishable keys, not secrets. The secret key never touches the app.
## Empty means "not configured yet"; we skip initialize() rather than handing the
## SDK a bad key and eating an unhelpful native error.
const API_KEY_ANDROID := "goog_tWyGxaFXcGXZSSTbZkLSQsZZVkn"
const API_KEY_IOS := ""       # appl_... — fill in only if iOS ships

## RevenueCat project identifiers, kept here for reference. Neither is needed to
## configure the SDK: the REST id addresses this app in REST/webhook calls, and
## the custom URL scheme is used by RevenueCat web/paywall redirects back into
## the app. Recorded so they aren't hunted for again later.
const RC_REST_APP_ID := "app542f1ae711"
const RC_URL_SCHEME := "rc-542f1ae711"

## Entitlement id as configured in the RevenueCat dashboard.
const ENTITLEMENT_PUBLISHER := "publisher_deal"

## Store product ids. Must match Play Console exactly.
const PRODUCT_PUBLISHER_DEAL := "publisher_deal"
const PRODUCT_TOKENS_SMALL := "tokens_small"
const PRODUCT_TOKENS_LARGE := "tokens_large"
const PRODUCT_DEV_SUPPORT  := "developer_support"

## Token grants for the consumable packs. Kept here rather than trusting a
## store-side value so the reward is identical no matter what the receipt says.
const TOKEN_PACK_GRANTS := {
	PRODUCT_DEV_SUPPORT: 15,
	PRODUCT_TOKENS_SMALL: 25,
	PRODUCT_TOKENS_LARGE: 90,
}

## Every entitlement we care about. Refreshed via check_entitlement() whenever
## customer info changes.
const TRACKED_ENTITLEMENTS := [ENTITLEMENT_PUBLISHER]

## Flip to true ONLY when a real ad network is wired into show_rewarded().
## Until then this keeps every ad offer hidden in release builds — without it a
## shipped Android build would show "Watch an ad" buttons whose only possible
## reply is "no ad available". Debug builds ignore this and simulate, so the
## flow stays testable on PC.
const ADS_WIRED := false

## Rewarded-ad placements. Passed to show_rewarded() and echoed back on the
## reward signal so a caller can tell its own reward from someone else's.
const PLACEMENT_DOUBLE_TOKENS := "double_tokens"
const PLACEMENT_SKILL_TRIAL := "skill_trial"

## ─── SIGNALS ────────────────────────────────────────────────────────────

## Any tracked entitlement changed state. UI should re-read owns_publisher_deal().
signal entitlements_changed()
## A purchase completed and has already been applied to Global.
signal purchase_succeeded(product_id: String)
## A purchase failed or was cancelled. `reason` is user-presentable-ish.
signal purchase_failed(reason: String)
## Restore finished. `ok` is false when the native call reported an error.
signal restore_finished(ok: bool)
## The player watched a rewarded ad to completion. Grant the reward now.
signal ad_reward_granted(placement: String)
## No ad was available, or the player dismissed it early. Nothing was earned.
signal ad_unavailable(placement: String)
## Localized store prices arrived (or changed). Read them with price_for().
signal prices_updated()

## ─── STATE ──────────────────────────────────────────────────────────────

## True when the native singleton is present AND a key was configured.
var available: bool = false

var _rc = null
## Last known entitlement state, mirrored into Global so it survives a cold
## start with no network. Advisory only — the SDK is authoritative and
## overwrites this on every customer_info_changed.
var _entitlements: Dictionary = {}
## Product id of the purchase currently in flight, so purchase_result (which
## does not reliably echo the id back on every platform) can be attributed.
var _pending_product: String = ""
## True between restore() and its result, so the timeout can tell a silent
## failure from a result that already landed.
var _restore_pending: bool = false
## AdMob adapter instance, created on first use. Null when the plugin is absent.
var _admob_node: Node = null
## product id -> localized price string ("$0.99"), filled by fetch_prices().
var _prices: Dictionary = {}


func _ready() -> void:
	# Restore the cached entitlements before anything reads them. IAP is listed
	# LAST in project.godot's autoload block on purpose: Global must have loaded
	# meta.dat and LeaderboardService must have its player_id before we run.
	_entitlements = Global.iap_entitlements.duplicate()

	if not Engine.has_singleton("GodotxRevenueCat"):
		print("[IAP] Native singleton absent — running with purchases disabled.")
		return
	var key := _api_key()
	if key == "":
		print("[IAP] Singleton present but no API key configured — skipping init.")
		return

	_rc = Engine.get_singleton("GodotxRevenueCat")
	# The plugin DECLARES customer_info_changed but (as of the source we have)
	# never emits it — only `customer_info`, from get_customer_info(). Connect
	# both: whichever the installed build actually fires, we re-sync.
	if _rc.has_signal("customer_info_changed"):
		_rc.customer_info_changed.connect(_on_customer_info_changed)
	if _rc.has_signal("customer_info"):
		_rc.customer_info.connect(_on_customer_info_changed)
	_rc.purchase_result.connect(_on_purchase_result)
	_rc.restore_finished.connect(_on_restore_finished)
	_rc.entitlement.connect(_on_entitlement)
	_rc.paywall_result.connect(_on_paywall_result)
	if _rc.has_signal("products"):
		_rc.products.connect(_on_products)

	# Tie purchases to the leaderboard identity so they survive a reinstall.
	# Without this every install is a fresh anonymous RevenueCat user and a
	# reinstalled player silently loses what they paid for.
	_rc.initialize(key, _stable_user_id(), OS.is_debug_build())
	available = true
	print("[IAP] Initialised (debug=%s)." % OS.is_debug_build())
	_refresh_entitlements()
	fetch_prices()


func _api_key() -> String:
	return API_KEY_IOS if OS.get_name() == "iOS" else API_KEY_ANDROID


## RevenueCat app user id. Reuses the leaderboard identity when one exists so a
## player's purchases and their scoreboard entry describe the same person.
## Returns "" to let RevenueCat generate an anonymous id.
func _stable_user_id() -> String:
	var lb = get_node_or_null("/root/LeaderboardService")
	if lb == null: return ""
	for prop in ["player_id", "device_id", "user_id"]:
		var v = lb.get(prop)
		if typeof(v) == TYPE_STRING and v != "":
			return String(v)
	return ""


## ─── ENTITLEMENT QUERIES ────────────────────────────────────────────────

## Synchronous, cache-backed. Safe to call from _draw/_process — the shop UI
## redraws constantly and cannot await a native round trip.
func has_entitlement(id: String) -> bool:
	return bool(_entitlements.get(id, false))


func owns_publisher_deal() -> bool:
	return has_entitlement(ENTITLEMENT_PUBLISHER)


## Ask the SDK to re-report every entitlement we track. Results arrive
## asynchronously on the `entitlement` signal.
func _refresh_entitlements() -> void:
	if not available: return
	for id in TRACKED_ENTITLEMENTS:
		_rc.check_entitlement(id)


func _set_entitlement(id: String, active: bool) -> void:
	if bool(_entitlements.get(id, false)) == active:
		return
	_entitlements[id] = active
	# Mirror into the save blob so an offline cold start still honours it.
	Global.iap_entitlements = _entitlements.duplicate()
	Global.save_state()
	entitlements_changed.emit()


## ─── PRICES ─────────────────────────────────────────────────────────────

## Ask the store for localized prices of every product the in-game store sells.
## Safe to call repeatedly; results land on prices_updated.
func fetch_prices() -> void:
	if not available or not _rc.has_method("fetch_products"): return
	_rc.fetch_products([PRODUCT_TOKENS_SMALL, PRODUCT_TOKENS_LARGE,
		PRODUCT_PUBLISHER_DEAL, PRODUCT_DEV_SUPPORT])


## Localized price, or "" when the store hasn't reported one (yet).
func price_for(product_id: String) -> String:
	return String(_prices.get(product_id, ""))


func _on_products(data) -> void:
	if _error_of(data) != "" or typeof(data) != TYPE_DICTIONARY: return
	var raw = data.get("products", null)
	var items: Array = []
	# iOS hands back a native Array, Android a java.util.List.
	if raw is Array:
		items = raw
	elif raw is JavaObject:
		for i in int(raw.call("size")):
			items.append(raw.call("get", i))
	for prod in items:
		if typeof(prod) != TYPE_DICTIONARY: continue
		# Play subscriptions report "id:base-plan"; the store only knows the id.
		var pid := String(prod.get("id", "")).get_slice(":", 0)
		if pid != "":
			_prices[pid] = String(prod.get("price", ""))
	prices_updated.emit()


## ─── PURCHASE FLOW ──────────────────────────────────────────────────────

## Start a purchase. No-ops (and reports failure) when the store is absent, so
## callers can wire a button unconditionally.
func purchase(product_id: String) -> void:
	if not available:
		purchase_failed.emit("Store unavailable")
		return
	_pending_product = product_id
	_rc.purchase(product_id)


## Show RevenueCat's native paywall for an offering. Cheaper than building our
## own; revisit if the Design Award becomes a target (for_hackathon.md §4).
func present_paywall(offering: String = "default") -> void:
	if not available:
		purchase_failed.emit("Store unavailable")
		return
	_rc.present_paywall(offering)


## Restore. Guarded by a timeout because the plugin's restorePurchasesWith()
## call passes no onError handler — a failed restore emits nothing at all, and
## a UI awaiting restore_finished would hang forever.
func restore() -> void:
	if not available:
		restore_finished.emit(false)
		return
	_restore_pending = true
	_rc.restore_purchases()
	await get_tree().create_timer(20.0).timeout
	if _restore_pending:
		_restore_pending = false
		restore_finished.emit(false)


## Deep-link to the platform's own subscription management screen. Both stores
## require this to be reachable from inside the app.
func manage_subscriptions() -> void:
	if not available: return
	if _rc.has_method("show_manage_subscriptions"):
		_rc.show_manage_subscriptions()


func _on_customer_info_changed(_data) -> void:
	# The payload shape differs between iOS (Dictionary) and Android
	# (JavaObject), so rather than parse it we re-ask for the entitlements we
	# actually care about through the typed check_entitlement() path.
	_refresh_entitlements()


func _on_entitlement(id: String, active: bool) -> void:
	_set_entitlement(id, active)


func _on_purchase_result(data) -> void:
	var err := _error_of(data)
	if err != "":
		_pending_product = ""
		purchase_failed.emit(err)
		return
	var pid := _pending_product
	if pid == "":
		pid = _string_field(data, "product_id")
	_pending_product = ""
	_apply_purchase(pid)
	_refresh_entitlements()
	purchase_succeeded.emit(pid)


func _on_restore_finished(data) -> void:
	_restore_pending = false
	_refresh_entitlements()
	if _error_of(data) != "":
		restore_finished.emit(false)
		return
	# The plugin reports `restored` (true only when something came back) rather
	# than an error on the nothing-to-restore path. Absent key = treat as ok.
	if typeof(data) == TYPE_DICTIONARY and data.has("restored"):
		restore_finished.emit(bool(data["restored"]))
		return
	restore_finished.emit(true)


func _on_paywall_result(_data) -> void:
	# The paywall closes on both purchase and dismissal; a real purchase also
	# fires customer_info_changed, so just re-sync and let that drive the UI.
	_refresh_entitlements()


## Credit whatever a completed purchase is worth. Entitlements (the Publisher
## Deal) are driven by the SDK, so only the consumable token packs are handled
## here — they have no entitlement to read back.
func _apply_purchase(product_id: String) -> void:
	if TOKEN_PACK_GRANTS.has(product_id):
		Global.add_tokens_flat(int(TOKEN_PACK_GRANTS[product_id]))
		Global.save_state()


## ─── REWARDED ADS ───────────────────────────────────────────────────────

## Show a rewarded ad for `placement` and await the outcome:
##     if await IAP.show_rewarded(IAP.PLACEMENT_DOUBLE_TOKENS): grant()
## Returns true only when the player actually earned the reward. The matching
## signal is emitted too, for anything that wants to observe without awaiting.
##
## NOTE: godotx_revenue_cat exposes purchases only; RevenueCat Ads has no Godot
## binding in it. Wiring a real ad network is still outstanding work. Until
## then debug builds grant the reward immediately so the whole game-side flow
## (offer → reward → grant) is testable now, and release builds report no fill
## rather than handing out free rewards.
func show_rewarded(placement: String) -> bool:
	var ads := _admob()
	if ads != null:
		var earned: bool = await ads.show_rewarded()
		if earned:
			ad_reward_granted.emit(placement)
		else:
			ad_unavailable.emit(placement)
		return earned
	if OS.is_debug_build():
		print("[IAP] No AdMob plugin — simulating rewarded ad for '%s'." % placement)
		# Deferred so callers observe the same async shape a real ad has.
		await get_tree().create_timer(0.4).timeout
		ad_reward_granted.emit(placement)
		return true
	ad_unavailable.emit(placement)
	return false


## Lazily bring up the AdMob adapter, and only if the plugin is actually
## installed. The class check matters: admob_ads.gd references plugin-only
## classes, so loading it without the plugin would throw. Returns null when
## ads are unavailable, which every caller already handles.
func _admob() -> Node:
	if _admob_node != null and is_instance_valid(_admob_node):
		return _admob_node
	if not ClassDB.class_exists("RewardedAdLoader"):
		return null
	if not ResourceLoader.exists("res://admob_ads.gd"):
		return null
	var scr = load("res://admob_ads.gd")
	if scr == null:
		return null
	_admob_node = scr.new()
	_admob_node.name = "AdMobAds"
	add_child(_admob_node)
	return _admob_node


## True when it is worth offering the player an ad at all.
## Disabled: focus is solely on real RevenueCat purchases/entitlements.
func ads_enabled() -> bool:
	return false


## ─── PAYLOAD HELPERS ────────────────────────────────────────────────────
## Both platforms hand back loosely-typed blobs. These read a field without
## assuming Dictionary, so an unexpected JavaObject cannot crash a purchase.

func _string_field(data, key: String) -> String:
	if typeof(data) == TYPE_DICTIONARY:
		return String(data.get(key, ""))
	return ""


## Returns "" when the payload reports no error, otherwise the message.
func _error_of(data) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	var err := String(data.get("error", ""))
	if err != "":
		return err
	if bool(data.get("cancelled", false)) or bool(data.get("userCancelled", false)):
		return "Cancelled"
	return ""
