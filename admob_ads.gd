extends Node
## AdMob rewarded-ad adapter, loaded on demand by iap_manager.gd.
##
## IMPORTANT: this file references classes that only exist once the Poing Studios
## AdMob plugin is installed (MobileAds, RewardedAdLoader, RewardedAdLoadCallback,
## AdRequest, OnUserEarnedRewardListener). Until you install it, the Godot editor
## will show parse errors HERE and nowhere else — the game is unaffected, because
## IAP only ever loads this script after checking the plugin's classes exist.
##
## SETUP:
##   1. Install "AdMob" by Poing Studios from the Godot Asset Library and enable it.
##   2. Put your AdMob App ID in the plugin's export settings (Project Settings →
##      AdMob, or the plugin's own config) — the app will crash on launch without it.
##   3. Create a Rewarded ad unit in the AdMob console, paste it into
##      REWARDED_UNIT_ANDROID below, and set USE_TEST_ADS = false for release.
##   4. Flip ADS_WIRED to true in iap_manager.gd.

## Google's official test ad unit. ALWAYS use test ads during development —
## loading or clicking your own live ads is a policy violation and AdMob will
## suspend the account for it. This is not a nicety; people lose accounts to it.
const TEST_REWARDED_ANDROID := "ca-app-pub-3940256099942544/5224354917"

## Your real rewarded unit, from the AdMob console. Format: ca-app-pub-XXXX/YYYY
const REWARDED_UNIT_ANDROID := ""

## Keep true until you are shipping. Also acts as a safety net: an empty
## REWARDED_UNIT_ANDROID falls back to the test unit rather than to a broken id.
const USE_TEST_ADS := true

## How long to wait for an ad to fill before giving up and telling the caller
## there was none. Longer than this and the player is just staring at a button.
const LOAD_TIMEOUT := 6.0

## Hard ceiling on waiting for the ad to close, in case the focus signal never
## arrives on some device. Rewarded ads run ~30s.
const SHOW_TIMEOUT := 180.0

var _loaded_ad = null
var _loading: bool = false

## Ad-presentation state. The plugin's own dismissal callback isn't documented,
## so we detect the ad closing via application focus instead: showing an ad
## takes focus away from the Godot activity, and closing it hands focus back.
## That needs no plugin API at all.
var _showing: bool = false
var _saw_focus_out: bool = false
var _closed: bool = false
var _reward_earned: bool = false


func _ready() -> void:
	MobileAds.initialize()
	_preload()


func _notification(what: int) -> void:
	if not _showing:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# The ad activity came up. Only now does a focus-in mean "closed".
			_saw_focus_out = true
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if _saw_focus_out:
				_closed = true


func _unit_id() -> String:
	if USE_TEST_ADS or REWARDED_UNIT_ANDROID == "":
		return TEST_REWARDED_ANDROID
	return REWARDED_UNIT_ANDROID


## Start fetching the next ad. Called at boot and again after every show, so a
## fill is usually already in hand by the time the player asks for one.
func _preload() -> void:
	if _loading or _loaded_ad != null:
		return
	_loading = true
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_failed_to_load = func(error):
		_loading = false
		_loaded_ad = null
		print("[AdMob] Rewarded load failed: ", error.message)
	cb.on_ad_loaded = func(ad):
		_loading = false
		_loaded_ad = ad
	RewardedAdLoader.new().load(_unit_id(), AdRequest.new(), cb)


## Show a rewarded ad. Returns true ONLY if the player earned the reward —
## dismissing early returns false and grants nothing.
func show_rewarded() -> bool:
	if _loaded_ad == null:
		_preload()
		var waited := 0.0
		while _loaded_ad == null and waited < LOAD_TIMEOUT:
			await get_tree().create_timer(0.2).timeout
			waited += 0.2
	if _loaded_ad == null:
		return false

	var ad = _loaded_ad
	# Drop our reference before showing: a rewarded ad is single-use, and
	# holding it invites a second show() that silently does nothing.
	_loaded_ad = null
	_showing = true
	_saw_focus_out = false
	_closed = false
	_reward_earned = false

	ad.show(OnUserEarnedRewardListener.new(func(_reward):
		_reward_earned = true
	))

	var waited := 0.0
	while not _closed and waited < SHOW_TIMEOUT:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2

	_showing = false
	var earned := _reward_earned
	# Line up the next one straight away.
	_preload()
	return earned
