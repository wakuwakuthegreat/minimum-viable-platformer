extends Node

# Firestore REST Client Singleton for gigs-6f94d
# Communicates using Godot's native HTTPRequest node.

signal submit_result_completed(success: bool, error_message: String)
signal level_leaderboard_loaded(level_seed: String, stat: String, results: Array, success: bool, error_message: String)
signal most_played_loaded(level_seed: String, results: Array, success: bool, error_message: String)
signal hall_of_fame_loaded(hall_of_fame: Dictionary, success: bool, error_message: String)
signal community_favorites_loaded(results: Array, success: bool, error_message: String)

const PROJECT_ID := "gigs-6f94d"
const BASE_URL := "https://firestore.googleapis.com/v1/projects/" + PROJECT_ID + "/databases/(default)/documents"

# Feature toggle for transactions (optional/advanced retry system)
@export var use_transactions: bool = false
@export var max_transaction_retries: int = 3
@export var base_retry_delay_sec: float = 0.5

# Cache TTL in seconds — leaderboard data is cached for this long before re-fetching.
# Set to 0 to disable caching entirely.
@export var cache_ttl_sec: float = 300.0  # 5 minutes

# Unique player ID stored client-side
var player_id: String = ""

# The seed code currently targeted by the leaderboard view
var current_view_seed: String = ""

# ─── CACHE ────────────────────────────────────────────────────────────────────
# Structure: { cache_key: { "data": <payload>, "timestamp": <unix_sec> } }
var _cache: Dictionary = {}

func _cache_key_level(level_seed: String, stat: String) -> String:
	return "level:" + level_seed + ":" + stat

func _cache_key_plays(level_seed: String) -> String:
	return "plays:" + level_seed

const CACHE_KEY_HOF := "hof"
const CACHE_KEY_COMMUNITY := "community_favorites"

func _cache_get(key: String):
	if cache_ttl_sec <= 0.0:
		return null
	if not _cache.has(key):
		return null
	var entry: Dictionary = _cache[key]
	var age: float = Time.get_unix_time_from_system() - float(entry["timestamp"])
	if age > cache_ttl_sec:
		print("[LeaderboardService] Cache EXPIRED for '", key, "' (age=", int(age), "s)")
		_cache.erase(key)
		return null
	print("[LeaderboardService] Cache HIT for '", key, "' (age=", int(age), "s)")
	return entry["data"]

func _cache_set(key: String, data) -> void:
	_cache[key] = { "data": data, "timestamp": Time.get_unix_time_from_system() }
	print("[LeaderboardService] Cache SET '", key, "'")

func _cache_invalidate_for_seed(level_seed: String) -> void:
	var to_erase: Array = []
	for key in _cache.keys():
		if key.begins_with("level:" + level_seed) or key == "plays:" + level_seed or key == CACHE_KEY_HOF:
			to_erase.append(key)
	for key in to_erase:
		_cache.erase(key)
		print("[LeaderboardService] Cache INVALIDATED '", key, "'")

func _ready() -> void:
	# Load or generate player ID
	_setup_player_identity()

func _setup_player_identity() -> void:
	print("[LeaderboardService] Setting up player identity...")
	# Check if player_id exists in Global settings
	if Global.settings_cfg.has("player_id") and str(Global.settings_cfg["player_id"]) != "":
		player_id = str(Global.settings_cfg["player_id"])
		print("[LeaderboardService] Loaded existing player_id: ", player_id)
	else:
		# Generate a stable install-scoped unique ID
		var unique_id := OS.get_unique_id()
		if unique_id == "":
			print("[LeaderboardService] OS.get_unique_id() returned empty — using random fallback ID")
			unique_id = _generate_random_id()
		else:
			print("[LeaderboardService] OS.get_unique_id() returned: ", unique_id)
		
		player_id = unique_id
		Global.settings_cfg["player_id"] = player_id
		Global.save_state()
		print("[LeaderboardService] Generated and saved new player_id: ", player_id)
	
	print("[LeaderboardService] Player name: '", get_player_name(), "'  has_unique_name: ", has_unique_name())
	print("[LeaderboardService] Ready. use_transactions=", use_transactions)

func _generate_random_id() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var out := ""
	for i in 16:
		out += chars[randi() % chars.length()]
	return out

# Helper function to check if player name is a unique name
func has_unique_name() -> bool:
	var name_str: String = Global.settings_cfg.get("player_name", "").strip_edges()
	return name_str != "" and name_str.to_lower() != "anonymous" and name_str.to_lower() != "player"

# Helper function to get player name (fallback to "Anonymous" if not set)
func get_player_name() -> String:
	var name_str: String = Global.settings_cfg.get("player_name", "").strip_edges()
	if name_str == "":
		return "Anonymous"
	return name_str

# ─── UNIQUE NAME REGISTRY ───────────────────────────────────────────────────
# Names are claimed globally in the `names/{lower(name)}` collection, each doc
# holding the owning player_id. Claiming a taken name appends a small counter
# (Bob → Bob2 → Bob3 …) so a display name is stable and unique everywhere.

const MAX_NAME_ATTEMPTS := 20

## Resolve `desired` to a globally-unique name and claim it for this player,
## then invoke cb(resolved_name: String, was_suffixed: bool). On network failure
## we fall back to cb(desired, false) so offline play still submits.
func claim_unique_name(desired: String, cb: Callable) -> void:
	var base := desired.strip_edges()
	if base == "":
		cb.call(desired, false)
		return
	print("[LeaderboardService] claim_unique_name: desired='", base, "'")
	_try_claim_name(base, base, 1, cb)

## Try to claim `candidate`. If taken by another player, retry with base + n+1.
func _try_claim_name(base: String, candidate: String, attempt: int, cb: Callable) -> void:
	var doc_id := candidate.to_lower()
	var url := BASE_URL + "/names/" + doc_id.uri_encode()
	_http_request(url, HTTPClient.METHOD_GET, PackedStringArray(), "", func(result: int, code: int, headers: PackedStringArray, res_body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS:
			# Offline / connection error — accept the desired name unchanged.
			print("[LeaderboardService] claim_unique_name: network error, using '", candidate, "' as-is")
			_finalize_name(candidate, candidate != base, cb)
			return

		if code == 404:
			# Free — claim it.
			_write_name_claim(base, candidate, cb)
			return

		if code == 200:
			var json = JSON.parse_string(res_body.get_string_from_utf8())
			var owner_id := ""
			if json is Dictionary and json.has("fields"):
				var f: Dictionary = json["fields"]
				if f.has("player_id"):
					owner_id = str(_parse_firestore_value(f["player_id"]))
			if owner_id == player_id:
				# Already ours.
				print("[LeaderboardService] claim_unique_name: '", candidate, "' already owned by us")
				_finalize_name(candidate, candidate != base, cb)
				return
			# Taken by someone else — try the next suffix.
			if attempt >= MAX_NAME_ATTEMPTS:
				print("[LeaderboardService] claim_unique_name: exhausted attempts, falling back")
				_finalize_name(candidate, candidate != base, cb)
				return
			var next_attempt := attempt + 1
			_try_claim_name(base, base + str(next_attempt), next_attempt, cb)
			return

		# Unexpected code — accept desired.
		print("[LeaderboardService] claim_unique_name: unexpected HTTP ", code, ", using '", candidate, "'")
		_finalize_name(candidate, candidate != base, cb)
	)

func _write_name_claim(base: String, candidate: String, cb: Callable) -> void:
	var doc_id := candidate.to_lower()
	var url := BASE_URL + "/names/" + doc_id.uri_encode() + "?updateMask.fieldPaths=player_id&updateMask.fieldPaths=display_name"
	var payload := {
		"fields": {
			"player_id": { "stringValue": player_id },
			"display_name": { "stringValue": candidate }
		}
	}
	_http_request(url, HTTPClient.METHOD_PATCH, PackedStringArray(), JSON.stringify(payload), func(w_res: int, w_code: int, w_headers: PackedStringArray, w_body: PackedByteArray):
		if w_res != HTTPRequest.RESULT_SUCCESS or (w_code != 200 and w_code != 204):
			print("[LeaderboardService] claim_unique_name: claim write failed HTTP ", w_code, " — using '", candidate, "' anyway")
		else:
			print("[LeaderboardService] claim_unique_name: claimed '", candidate, "'")
		_finalize_name(candidate, candidate != base, cb)
	)

func _finalize_name(resolved: String, was_suffixed: bool, cb: Callable) -> void:
	Global.settings_cfg["player_name"] = resolved
	Global.settings_cfg["name_registered"] = true
	Global.save_state()
	cb.call(resolved, was_suffixed)

func name_is_registered() -> bool:
	return bool(Global.settings_cfg.get("name_registered", false))

# ─── HTTP REQUEST UTILITY ──────────────────────────────────────────────────

func _http_request(url: String, method: HTTPClient.Method, headers: PackedStringArray, body: String, callback: Callable) -> void:
	var method_name = ["GET","HEAD","POST","PUT","DELETE","OPTIONS","TRACE","CONNECT","PATCH"].get(method)
	print("[LeaderboardService] HTTP ", method_name, " ", url)
	if body != "" and body != "{}":
		print("[LeaderboardService]   body (truncated): ", body.left(200))
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray):
		var resp_preview := response_body.get_string_from_utf8().left(300)
		print("[LeaderboardService] ← HTTP ", method_name, " ", url.right(60), " | code=", response_code, " result=", result)
		if response_code >= 400 or result != HTTPRequest.RESULT_SUCCESS:
			print("[LeaderboardService]   ERROR body: ", resp_preview)
		callback.call(result, response_code, response_headers, response_body)
		http.queue_free()
	)
	
	var final_headers := headers.duplicate()
	var has_content_type := false
	for h in final_headers:
		if h.to_lower().begins_with("content-type:"):
			has_content_type = true
			break
	if not has_content_type and (method == HTTPClient.METHOD_POST or method == HTTPClient.METHOD_PATCH):
		final_headers.append("Content-Type: application/json")
	
	var err := http.request(url, final_headers, method, body)
	if err != OK:
		callback.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		http.queue_free()

# ─── FIRESTORE VALUE SERIALIZERS ───────────────────────────────────────────

func _parse_firestore_value(val: Dictionary):
	if val.has("stringValue"):
		return val["stringValue"]
	elif val.has("integerValue"):
		return int(val["integerValue"])
	elif val.has("doubleValue"):
		return float(val["doubleValue"])
	elif val.has("booleanValue"):
		return bool(val["booleanValue"])
	elif val.has("mapValue"):
		var map_fields: Dictionary = val["mapValue"].get("fields", {})
		var out := {}
		for k in map_fields.keys():
			out[k] = _parse_firestore_value(map_fields[k])
		return out
	elif val.has("arrayValue"):
		var arr_vals: Array = val["arrayValue"].get("values", [])
		var out := []
		for v in arr_vals:
			out.append(_parse_firestore_value(v))
		return out
	elif val.has("nullValue"):
		return null
	return null

func _serialize_to_firestore_value(val):
	if typeof(val) == TYPE_STRING:
		return { "stringValue": val }
	elif typeof(val) == TYPE_INT:
		return { "integerValue": str(val) }
	elif typeof(val) == TYPE_FLOAT:
		return { "doubleValue": val }
	elif typeof(val) == TYPE_BOOL:
		return { "booleanValue": val }
	elif typeof(val) == TYPE_NIL:
		return { "nullValue": null }
	elif typeof(val) == TYPE_DICTIONARY:
		var fields := {}
		for k in val.keys():
			fields[k] = _serialize_to_firestore_value(val[k])
		return { "mapValue": { "fields": fields } }
	elif typeof(val) == TYPE_ARRAY:
		var values := []
		for item in val:
			values.append(_serialize_to_firestore_value(item))
		return { "arrayValue": { "values": values } }
	return { "nullValue": null }

# ─── SUBMIT RESULT FLOW ────────────────────────────────────────────────────

func submit_level_result(level_seed: String, p_id: String, p_name: String, score: int, distance: int, combo: int) -> void:
	print("[LeaderboardService] submit_level_result: seed='%s' player='%s' id='%s' score=%d distance=%d combo=%d" % [level_seed, p_name, p_id, score, distance, combo])
	if level_seed == "":
		print("[LeaderboardService]   ABORT: empty level seed")
		emit_signal("submit_result_completed", false, "Invalid level seed")
		return
	
	# We have 3 parallel operations:
	# 1. Increment Play Count (Atomic Transform)
	# 2. Update level document (Best Score, Longest Distance, Highest Combo)
	# 3. Update global Hall of Fame
	
	var pending := 3
	var errors: Array[String] = []
	
	var on_task_done := func(err_msg: String):
		if err_msg != "":
			print("[LeaderboardService]   subtask error: ", err_msg)
			errors.append(err_msg)
		pending -= 1
		print("[LeaderboardService]   subtask done, remaining=", pending)
		if pending == 0:
			if errors.is_empty():
				print("[LeaderboardService] submit_level_result COMPLETE (all 3 tasks OK)")
				# Invalidate cache for this seed so the UI shows fresh data on next open
				_cache_invalidate_for_seed(level_seed)
				emit_signal("submit_result_completed", true, "")
			else:
				print("[LeaderboardService] submit_level_result COMPLETE with errors: ", errors)
				emit_signal("submit_result_completed", false, ", ".join(errors))
	
	# Task 1: Play Count Increment (Atomic Commit)
	print("[LeaderboardService]   starting Task 1: play count increment")
	_increment_play_count(level_seed, p_id, p_name, on_task_done)
	
	# Task 2: Level Leaderboards (GET + PATCH or Transactional)
	print("[LeaderboardService]   starting Task 2: level leaderboard update (tx=", use_transactions, ")")
	if use_transactions:
		_update_level_leaderboard_tx(level_seed, p_id, p_name, score, distance, combo, 0, on_task_done)
	else:
		_update_level_leaderboard_standard(level_seed, p_id, p_name, score, distance, combo, on_task_done)
		
	# Task 3: Global Hall of Fame (GET + PATCH or Transactional)
	print("[LeaderboardService]   starting Task 3: global HOF update (tx=", use_transactions, ")")
	if use_transactions:
		_update_global_hof_tx(level_seed, p_id, p_name, distance, combo, 0, on_task_done)
	else:
		_update_global_hof_standard(level_seed, p_id, p_name, distance, combo, on_task_done)

# ─── TASK 1: PLAY COUNT INCREMENT ──────────────────────────────────────────

func _increment_play_count(level_seed: String, p_id: String, p_name: String, callback: Callable) -> void:
	print("[LeaderboardService] Task1: incrementing play count for seed='%s' player='%s'" % [level_seed, p_name])
	var url := BASE_URL + ":commit"
	var doc_path := "projects/" + PROJECT_ID + "/databases/(default)/documents/leaderboards/" + level_seed + "/plays/" + p_id
	
	var payload := {
		"writes": [
			{
				"update": {
					"name": doc_path,
					"fields": {
						"player_name": { "stringValue": p_name }
					}
				},
				"updateMask": {
					"fieldPaths": ["player_name"]
				},
				"updateTransforms": [
					{
						"fieldPath": "count",
						"increment": { "integerValue": "1" }
					}
				]
			}
		]
	}
	
	var body := JSON.stringify(payload)
	_http_request(url, HTTPClient.METHOD_POST, PackedStringArray(), body, func(result: int, code: int, headers: PackedStringArray, res_body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 204):
			var response_str := res_body.get_string_from_utf8()
			print("[LeaderboardService] Task1 FAILED: HTTP ", code, " — ", response_str.left(200))
			callback.call("Play count increment failed (HTTP " + str(code) + "): " + response_str)
		else:
			print("[LeaderboardService] Task1 OK: play count incremented")
			callback.call("")
	)

# ─── TASK 2: LEVEL LEADERBOARD (STANDARD / TX) ──────────────────────────────

func _update_level_leaderboard_standard(level_seed: String, p_id: String, p_name: String, score: int, distance: int, combo: int, callback: Callable) -> void:
	print("[LeaderboardService] Task2 (standard): fetching level doc for seed='", level_seed, "'")
	# 1. GET level doc
	var url := BASE_URL + "/leaderboards/" + level_seed
	_http_request(url, HTTPClient.METHOD_GET, PackedStringArray(), "", func(result: int, code: int, headers: PackedStringArray, res_body: PackedByteArray):
		var doc_fields := {}
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json = JSON.parse_string(res_body.get_string_from_utf8())
			if json is Dictionary and json.has("fields"):
				var raw_fields: Dictionary = json["fields"]
				for k in raw_fields.keys():
					doc_fields[k] = _parse_firestore_value(raw_fields[k])
			print("[LeaderboardService] Task2: level doc fetched, fields=", doc_fields.keys())
		elif result == HTTPRequest.RESULT_SUCCESS and code == 404:
			# Document doesn't exist yet, which is fine
			print("[LeaderboardService] Task2: level doc not found (404) — will create")
		elif result != HTTPRequest.RESULT_SUCCESS:
			print("[LeaderboardService] Task2 FAILED: HTTP connection error")
			callback.call("Failed to fetch level leaderboard (HTTP error)")
			return
		
		# 2. Check and modify arrays
		var dirty := _process_leaderboard_arrays(doc_fields, p_id, p_name, score, distance, combo)
		
		if not dirty:
			# No records beaten, no write needed!
			print("[LeaderboardService] Task2: no records beaten, skipping write")
			callback.call("")
			return
		
		print("[LeaderboardService] Task2: records updated, PATCHing back...")
		# 3. PATCH level doc back
		var patch_url := BASE_URL + "/leaderboards/" + level_seed + "?updateMask.fieldPaths=best_score&updateMask.fieldPaths=longest_distance&updateMask.fieldPaths=highest_combo"
		var patch_payload := {
			"fields": {
				"best_score": _serialize_to_firestore_value(doc_fields.get("best_score", [])),
				"longest_distance": _serialize_to_firestore_value(doc_fields.get("longest_distance", [])),
				"highest_combo": _serialize_to_firestore_value(doc_fields.get("highest_combo", []))
			}
		}
		var patch_body := JSON.stringify(patch_payload)
		_http_request(patch_url, HTTPClient.METHOD_PATCH, PackedStringArray(), patch_body, func(w_res: int, w_code: int, w_headers: PackedStringArray, w_res_body: PackedByteArray):
			if w_res != HTTPRequest.RESULT_SUCCESS or (w_code != 200 and w_code != 204):
				var res_str := w_res_body.get_string_from_utf8()
				print("[LeaderboardService] Task2 PATCH FAILED: HTTP ", w_code, " — ", res_str.left(200))
				callback.call("Failed to update level leaderboard (HTTP " + str(w_code) + "): " + res_str)
			else:
				print("[LeaderboardService] Task2 OK: level leaderboard updated")
				callback.call("")
		)
	)

func _update_level_leaderboard_tx(level_seed: String, p_id: String, p_name: String, score: int, distance: int, combo: int, attempt: int, callback: Callable) -> void:
	# Transaction implementation
	# 1. Begin Transaction
	var begin_url := BASE_URL + ":beginTransaction"
	_http_request(begin_url, HTTPClient.METHOD_POST, PackedStringArray(), "{}", func(t_res: int, t_code: int, t_hdrs: PackedStringArray, t_body: PackedByteArray):
		if t_res != HTTPRequest.RESULT_SUCCESS or t_code != 200:
			callback.call("Tx begin failed (HTTP " + str(t_code) + ")")
			return
		var t_json = JSON.parse_string(t_body.get_string_from_utf8())
		if not t_json is Dictionary or not t_json.has("transaction"):
			callback.call("Tx token not found in response")
			return
		var tx_token: String = t_json["transaction"]
		
		# 2. Get document in transaction via batchGet
		var get_url := BASE_URL + ":batchGet"
		var get_payload := {
			"documents": [
				"projects/" + PROJECT_ID + "/databases/(default)/documents/leaderboards/" + level_seed
			],
			"transaction": tx_token
		}
		_http_request(get_url, HTTPClient.METHOD_POST, PackedStringArray(), JSON.stringify(get_payload), func(g_res: int, g_code: int, g_hdrs: PackedStringArray, g_body: PackedByteArray):
			if g_res != HTTPRequest.RESULT_SUCCESS or g_code != 200:
				callback.call("Tx doc fetch failed (HTTP " + str(g_code) + ")")
				return
			
			var g_json = JSON.parse_string(g_body.get_string_from_utf8())
			var doc_fields := {}
			if g_json is Array and g_json.size() > 0:
				var first_entry = g_json[0]
				if first_entry is Dictionary and first_entry.has("found"):
					var found_doc = first_entry["found"]
					if found_doc.has("fields"):
						var raw_fields: Dictionary = found_doc["fields"]
						for k in raw_fields.keys():
							doc_fields[k] = _parse_firestore_value(raw_fields[k])
			
			# 3. Process changes
			var dirty := _process_leaderboard_arrays(doc_fields, p_id, p_name, score, distance, combo)
			if not dirty:
				# Tx complete: no updates needed. Just return.
				callback.call("")
				return
			
			# 4. Commit write
			var commit_url := BASE_URL + ":commit"
			var doc_path := "projects/" + PROJECT_ID + "/databases/(default)/documents/leaderboards/" + level_seed
			var commit_payload := {
				"writes": [
					{
						"update": {
							"name": doc_path,
							"fields": {
								"best_score": _serialize_to_firestore_value(doc_fields.get("best_score", [])),
								"longest_distance": _serialize_to_firestore_value(doc_fields.get("longest_distance", [])),
								"highest_combo": _serialize_to_firestore_value(doc_fields.get("highest_combo", []))
							}
						},
						"updateMask": {
							"fieldPaths": ["best_score", "longest_distance", "highest_combo"]
						}
					}
				],
				"transaction": tx_token
			}
			
			_http_request(commit_url, HTTPClient.METHOD_POST, PackedStringArray(), JSON.stringify(commit_payload), func(c_res: int, c_code: int, c_hdrs: PackedStringArray, c_body: PackedByteArray):
				if c_res != HTTPRequest.RESULT_SUCCESS or c_code != 200:
					# Retry transaction with backoff
					if attempt < max_transaction_retries:
						var delay := base_retry_delay_sec * pow(2.0, attempt)
						await get_tree().create_timer(delay).timeout
						_update_level_leaderboard_tx(level_seed, p_id, p_name, score, distance, combo, attempt + 1, callback)
					else:
						callback.call("Tx level commit failed after " + str(max_transaction_retries) + " retries (HTTP " + str(c_code) + ")")
				else:
					callback.call("")
			)
		)
	)

func _process_leaderboard_arrays(doc_fields: Dictionary, p_id: String, p_name: String, score: int, distance: int, combo: int) -> bool:
	var dirty := false

	# Helper function to merge one player's value into a stat array, keeping a
	# SINGLE entry per player (their highest value). Returns true if the array
	# changed. Entries carry a hidden player_id so we can tell two players who
	# share a display name apart, and recognise a returning player.
	var process_stat := func(arr_key: String, new_val: int) -> bool:
		var raw_arr = doc_fields.get(arr_key, [])
		if not raw_arr is Array:
			raw_arr = []
		var arr: Array = raw_arr.duplicate(true)

		# 1. Does this player already hold a slot? (Legacy entries have no
		#    player_id and are treated as belonging to nobody, so they age out.)
		var existing_idx := -1
		for i in arr.size():
			var e = arr[i]
			if e is Dictionary and str(e.get("player_id", "")) == p_id and p_id != "":
				existing_idx = i
				break

		if existing_idx != -1:
			# Only improve — never add a second row for the same player.
			var cur_val := int(arr[existing_idx].get("score", 0))
			if new_val <= cur_val:
				return false
			arr[existing_idx]["score"] = new_val
			arr[existing_idx]["player_name"] = p_name
		else:
			# New player — qualifies if there's room or they beat the last slot.
			var qualifies := false
			if arr.size() < 10:
				qualifies = true
			else:
				var min_entry = arr[arr.size() - 1]
				if min_entry is Dictionary and new_val > int(min_entry.get("score", 0)):
					qualifies = true
			if not qualifies:
				return false
			arr.append({
				"player_id": p_id,
				"player_name": p_name,
				"score": new_val
			})

		# Sort descending, trim to 10.
		arr.sort_custom(func(a, b):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		)
		if arr.size() > 10:
			arr = arr.slice(0, 10)
		doc_fields[arr_key] = arr
		return true


	if process_stat.call("best_score", score):
		print("[LeaderboardService]   best_score array updated (new entry score=", score, ")")
		dirty = true
	if process_stat.call("longest_distance", distance):
		print("[LeaderboardService]   longest_distance array updated (new entry distance=", distance, ")")
		dirty = true
	if process_stat.call("highest_combo", combo):
		print("[LeaderboardService]   highest_combo array updated (new entry combo=", combo, ")")
		dirty = true

	if not dirty:
		print("[LeaderboardService]   no array changes (score/distance/combo did not qualify)")

	return dirty

# ─── TASK 3: GLOBAL HALL OF FAME (STANDARD / TX) ────────────────────────────

const HOF_TOP_N := 3

## Normalize a Hall-of-Fame stat field into an array of record dicts. Legacy
## documents stored a single {player_name, value, level_id} map — wrap it so the
## top-3 logic can treat both shapes uniformly.
func _hof_stat_to_array(raw) -> Array:
	if raw is Array:
		return raw.duplicate(true)
	if raw is Dictionary and raw.has("value"):
		return [raw.duplicate(true)]
	return []

## Merge one player's value into a HOF stat array, keeping the top HOF_TOP_N
## with a single (highest) entry per player. Returns {"arr":Array,"changed":bool}.
func _merge_hof_stat(raw, p_id: String, p_name: String, value: int, level_id: String) -> Dictionary:
	var arr := _hof_stat_to_array(raw)
	var before := JSON.stringify(arr)

	var existing_idx := -1
	for i in arr.size():
		var e = arr[i]
		if e is Dictionary and str(e.get("player_id", "")) == p_id and p_id != "":
			existing_idx = i
			break

	if existing_idx != -1:
		if value > int(arr[existing_idx].get("value", 0)):
			arr[existing_idx]["value"] = value
			arr[existing_idx]["level_id"] = level_id
			arr[existing_idx]["player_name"] = p_name
	else:
		arr.append({
			"player_id": p_id,
			"player_name": p_name,
			"value": value,
			"level_id": level_id
		})

	arr.sort_custom(func(a, b):
		return int(a.get("value", 0)) > int(b.get("value", 0))
	)
	if arr.size() > HOF_TOP_N:
		arr = arr.slice(0, HOF_TOP_N)

	return { "arr": arr, "changed": JSON.stringify(arr) != before }

func _update_global_hof_standard(level_seed: String, p_id: String, p_name: String, distance: int, combo: int, callback: Callable) -> void:
	print("[LeaderboardService] Task3 (standard): fetching global HOF")
	# 1. GET global/hall_of_fame
	var url := BASE_URL + "/global/hall_of_fame"
	_http_request(url, HTTPClient.METHOD_GET, PackedStringArray(), "", func(result: int, code: int, headers: PackedStringArray, res_body: PackedByteArray):
		var doc_fields := {}
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json = JSON.parse_string(res_body.get_string_from_utf8())
			if json is Dictionary and json.has("fields"):
				var raw_fields: Dictionary = json["fields"]
				for k in raw_fields.keys():
					doc_fields[k] = _parse_firestore_value(raw_fields[k])
			print("[LeaderboardService] Task3: HOF fetched, fields=", doc_fields.keys())
		elif result == HTTPRequest.RESULT_SUCCESS and code == 404:
			print("[LeaderboardService] Task3: HOF doc not found (404) — will create")
		elif result != HTTPRequest.RESULT_SUCCESS:
			print("[LeaderboardService] Task3 FAILED: HTTP connection error")
			callback.call("Failed to fetch global HOF (HTTP error)")
			return

		var updates := {}
		var mask := PackedStringArray()

		# 2. Merge combo into the top-3 array.
		var combo_res := _merge_hof_stat(doc_fields.get("highest_combo"), p_id, p_name, combo, level_seed)
		if combo_res["changed"]:
			print("[LeaderboardService] Task3: highest_combo top-3 updated")
			updates["highest_combo"] = _serialize_to_firestore_value(combo_res["arr"])
			mask.append("highest_combo")

		# 3. Merge distance into the top-3 array.
		var dist_res := _merge_hof_stat(doc_fields.get("longest_distance"), p_id, p_name, distance, level_seed)
		if dist_res["changed"]:
			print("[LeaderboardService] Task3: longest_distance top-3 updated")
			updates["longest_distance"] = _serialize_to_firestore_value(dist_res["arr"])
			mask.append("longest_distance")

		if updates.is_empty():
			print("[LeaderboardService] Task3: no HOF records beaten, skipping write")
			callback.call("")
			return

		print("[LeaderboardService] Task3: PATCHing HOF with fields=", mask)
		# 4. PATCH global/hall_of_fame back
		var mask_query := "updateMask.fieldPaths=" + "&updateMask.fieldPaths=".join(mask)
		var patch_url := BASE_URL + "/global/hall_of_fame?" + mask_query
		var patch_payload := {
			"fields": updates
		}
		var patch_body := JSON.stringify(patch_payload)
		_http_request(patch_url, HTTPClient.METHOD_PATCH, PackedStringArray(), patch_body, func(w_res: int, w_code: int, w_headers: PackedStringArray, w_res_body: PackedByteArray):
			if w_res != HTTPRequest.RESULT_SUCCESS or (w_code != 200 and w_code != 204):
				var res_str := w_res_body.get_string_from_utf8()
				print("[LeaderboardService] Task3 PATCH FAILED: HTTP ", w_code, " — ", res_str.left(200))
				callback.call("Failed to update global HOF (HTTP " + str(w_code) + "): " + res_str)
			else:
				print("[LeaderboardService] Task3 OK: global HOF updated")
				callback.call("")
		)
	)

func _update_global_hof_tx(level_seed: String, p_id: String, p_name: String, distance: int, combo: int, attempt: int, callback: Callable) -> void:
	# Transaction implementation for HOF
	var begin_url := BASE_URL + ":beginTransaction"
	_http_request(begin_url, HTTPClient.METHOD_POST, PackedStringArray(), "{}", func(t_res: int, t_code: int, t_hdrs: PackedStringArray, t_body: PackedByteArray):
		if t_res != HTTPRequest.RESULT_SUCCESS or t_code != 200:
			callback.call("Tx HOF begin failed (HTTP " + str(t_code) + ")")
			return
		var t_json = JSON.parse_string(t_body.get_string_from_utf8())
		var tx_token: String = t_json.get("transaction", "")
		if tx_token == "":
			callback.call("Tx HOF token not found")
			return
			
		var get_url := BASE_URL + ":batchGet"
		var get_payload := {
			"documents": [
				"projects/" + PROJECT_ID + "/databases/(default)/documents/global/hall_of_fame"
			],
			"transaction": tx_token
		}
		_http_request(get_url, HTTPClient.METHOD_POST, PackedStringArray(), JSON.stringify(get_payload), func(g_res: int, g_code: int, g_hdrs: PackedStringArray, g_body: PackedByteArray):
			if g_res != HTTPRequest.RESULT_SUCCESS or g_code != 200:
				callback.call("Tx HOF fetch failed")
				return
				
			var g_json = JSON.parse_string(g_body.get_string_from_utf8())
			var doc_fields := {}
			if g_json is Array and g_json.size() > 0:
				var first_entry = g_json[0]
				if first_entry is Dictionary and first_entry.has("found"):
					var found_doc = first_entry["found"]
					if found_doc.has("fields"):
						var raw_fields: Dictionary = found_doc["fields"]
						for k in raw_fields.keys():
							doc_fields[k] = _parse_firestore_value(raw_fields[k])
							
			var updates := {}
			var mask := PackedStringArray()

			var combo_res := _merge_hof_stat(doc_fields.get("highest_combo"), p_id, p_name, combo, level_seed)
			if combo_res["changed"]:
				updates["highest_combo"] = _serialize_to_firestore_value(combo_res["arr"])
				mask.append("highest_combo")

			var dist_res := _merge_hof_stat(doc_fields.get("longest_distance"), p_id, p_name, distance, level_seed)
			if dist_res["changed"]:
				updates["longest_distance"] = _serialize_to_firestore_value(dist_res["arr"])
				mask.append("longest_distance")

			if updates.is_empty():
				callback.call("")
				return
				
			var commit_url := BASE_URL + ":commit"
			var doc_path := "projects/" + PROJECT_ID + "/databases/(default)/documents/global/hall_of_fame"
			var commit_payload := {
				"writes": [
					{
						"update": {
							"name": doc_path,
							"fields": updates
						},
						"updateMask": {
							"fieldPaths": mask
						}
					}
				],
				"transaction": tx_token
			}
			
			_http_request(commit_url, HTTPClient.METHOD_POST, PackedStringArray(), JSON.stringify(commit_payload), func(c_res: int, c_code: int, c_hdrs: PackedStringArray, c_body: PackedByteArray):
				if c_res != HTTPRequest.RESULT_SUCCESS or c_code != 200:
					if attempt < max_transaction_retries:
						var delay := base_retry_delay_sec * pow(2.0, attempt)
						await get_tree().create_timer(delay).timeout
						_update_global_hof_tx(level_seed, p_id, p_name, distance, combo, attempt + 1, callback)
					else:
						callback.call("Tx HOF commit failed after " + str(max_transaction_retries) + " retries")
				else:
					callback.call("")
			)
		)
	)

# ─── QUERY FUNCTIONS ───────────────────────────────────────────────────────

func get_level_leaderboard(level_seed: String, stat: String) -> void:
	print("[LeaderboardService] get_level_leaderboard: seed='", level_seed, "' stat='", stat, "'")
	if level_seed == "":
		print("[LeaderboardService]   ABORT: empty level seed")
		emit_signal("level_leaderboard_loaded", level_seed, stat, [], false, "Invalid level seed")
		return
	
	# Check cache first
	var cached = _cache_get(_cache_key_level(level_seed, stat))
	if cached != null:
		emit_signal("level_leaderboard_loaded", level_seed, stat, cached, true, "")
		return
		
	var url := BASE_URL + "/leaderboards/" + level_seed
	_http_request(url, HTTPClient.METHOD_GET, PackedStringArray(), "", func(result: int, code: int, headers: PackedStringArray, res_body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS:
			print("[LeaderboardService] get_level_leaderboard FAILED: HTTP connection error")
			emit_signal("level_leaderboard_loaded", level_seed, stat, [], false, "HTTP connection error")
			return
			
		if code == 404:
			# Leaderboard has no entries yet, which is not an error
			print("[LeaderboardService] get_level_leaderboard: seed not found (404), returning empty")
			_cache_set(_cache_key_level(level_seed, stat), [])
			emit_signal("level_leaderboard_loaded", level_seed, stat, [], true, "")
			return
			
		if code != 200:
			print("[LeaderboardService] get_level_leaderboard FAILED: HTTP ", code)
			emit_signal("level_leaderboard_loaded", level_seed, stat, [], false, "Server returned error: HTTP " + str(code))
			return
			
		var json = JSON.parse_string(res_body.get_string_from_utf8())
		if json is Dictionary and json.has("fields"):
			var raw_fields: Dictionary = json["fields"]
			if raw_fields.has(stat):
				var parsed = _parse_firestore_value(raw_fields[stat])
				if parsed is Array:
					print("[LeaderboardService] get_level_leaderboard OK: ", parsed.size(), " entries for stat '", stat, "'")
					_cache_set(_cache_key_level(level_seed, stat), parsed)
					emit_signal("level_leaderboard_loaded", level_seed, stat, parsed, true, "")
					return
		
		# If field is missing or format is unexpected, return empty array with success
		print("[LeaderboardService] get_level_leaderboard: stat '", stat, "' not found in doc, returning empty")
		_cache_set(_cache_key_level(level_seed, stat), [])
		emit_signal("level_leaderboard_loaded", level_seed, stat, [], true, "")
	)

func get_most_played_leaderboard(level_seed: String) -> void:
	print("[LeaderboardService] get_most_played_leaderboard: seed='", level_seed, "'")
	if level_seed == "":
		emit_signal("most_played_loaded", level_seed, [], false, "Invalid level seed")
		return
	
	# Check cache first
	var cached = _cache_get(_cache_key_plays(level_seed))
	if cached != null:
		emit_signal("most_played_loaded", level_seed, cached, true, "")
		return
		
	var url := BASE_URL + "/leaderboards/" + level_seed + ":runQuery"
	var payload := {
		"structuredQuery": {
			"from": [
				{
					"collectionId": "plays"
				}
			],
			"orderBy": [
				{
					"field": { "fieldPath": "count" },
					"direction": "DESCENDING"
				}
			],
			"limit": 10
		}
	}
	
	var body := JSON.stringify(payload)
	_http_request(url, HTTPClient.METHOD_POST, PackedStringArray(), body, func(result: int, code: int, headers: PackedStringArray, res_body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS:
			print("[LeaderboardService] get_most_played_leaderboard FAILED: HTTP connection error")
			emit_signal("most_played_loaded", level_seed, [], false, "HTTP connection error")
			return
			
		if code != 200:
			print("[LeaderboardService] get_most_played_leaderboard FAILED: HTTP ", code)
			emit_signal("most_played_loaded", level_seed, [], false, "Server returned error: HTTP " + str(code))
			return
			
		var response_str := res_body.get_string_from_utf8()
		var json = JSON.parse_string(response_str)
		var list: Array = []
		
		if json is Array:
			for item in json:
				if item is Dictionary and item.has("document"):
					var doc = item["document"]
					if doc is Dictionary and doc.has("fields"):
						var raw_fields: Dictionary = doc["fields"]
						var player_name := ""
						var count := 0
						if raw_fields.has("player_name"):
							player_name = str(_parse_firestore_value(raw_fields["player_name"]))
						if raw_fields.has("count"):
							count = int(_parse_firestore_value(raw_fields["count"]))
						list.append({
							"player_name": player_name,
							"count": count
						})
						
		print("[LeaderboardService] get_most_played_leaderboard OK: ", list.size(), " entries")
		_cache_set(_cache_key_plays(level_seed), list)
		emit_signal("most_played_loaded", level_seed, list, true, "")
	)

func get_hall_of_fame() -> void:
	print("[LeaderboardService] get_hall_of_fame")
	
	# Check cache first
	var cached_hof = _cache_get(CACHE_KEY_HOF)
	if cached_hof != null:
		emit_signal("hall_of_fame_loaded", cached_hof, true, "")
		return
	var url := BASE_URL + "/global/hall_of_fame"
	_http_request(url, HTTPClient.METHOD_GET, PackedStringArray(), "", func(result: int, code: int, headers: PackedStringArray, res_body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS:
			print("[LeaderboardService] get_hall_of_fame FAILED: HTTP connection error")
			emit_signal("hall_of_fame_loaded", {}, false, "HTTP connection error")
			return
			
		if code == 404:
			print("[LeaderboardService] get_hall_of_fame: doc not found (404), returning empty")
			emit_signal("hall_of_fame_loaded", {}, true, "")
			return
			
		if code != 200:
			print("[LeaderboardService] get_hall_of_fame FAILED: HTTP ", code)
			emit_signal("hall_of_fame_loaded", {}, false, "Server returned error: HTTP " + str(code))
			return
			
		var json = JSON.parse_string(res_body.get_string_from_utf8())
		var out := {}
		if json is Dictionary and json.has("fields"):
			var raw_fields: Dictionary = json["fields"]
			for k in raw_fields.keys():
				out[k] = _parse_firestore_value(raw_fields[k])
				
		print("[LeaderboardService] get_hall_of_fame OK: fields=", out.keys())
		_cache_set(CACHE_KEY_HOF, out)
		emit_signal("hall_of_fame_loaded", out, true, "")
	)

# ─── COMMUNITY FAVOURITES ──────────────────────────────────────────────────
# Each player writes the seeds they've favourited to
# community_favorites/{player_id}; clients read every doc and aggregate a
# star-count per seed (how many players favourited it).

## Upload this player's favourited seed codes. Fire-and-forget; also busts the
## community cache so a subsequent fetch reflects the change.
func upload_favorite_seeds(seed_codes: Array) -> void:
	if player_id == "":
		print("[LeaderboardService] upload_favorite_seeds: no player_id, skipping")
		return
	var codes: Array = []
	for c in seed_codes:
		codes.append(str(c))
	print("[LeaderboardService] upload_favorite_seeds: ", codes.size(), " seeds")
	var url := BASE_URL + "/community_favorites/" + player_id.uri_encode() + "?updateMask.fieldPaths=player_name&updateMask.fieldPaths=seeds"
	var payload := {
		"fields": {
			"player_name": _serialize_to_firestore_value(get_player_name()),
			"seeds": _serialize_to_firestore_value(codes)
		}
	}
	_http_request(url, HTTPClient.METHOD_PATCH, PackedStringArray(), JSON.stringify(payload), func(w_res: int, w_code: int, w_headers: PackedStringArray, w_body: PackedByteArray):
		if w_res != HTTPRequest.RESULT_SUCCESS or (w_code != 200 and w_code != 204):
			print("[LeaderboardService] upload_favorite_seeds FAILED: HTTP ", w_code)
		else:
			print("[LeaderboardService] upload_favorite_seeds OK")
			_cache.erase(CACHE_KEY_COMMUNITY)
	)

## Fetch every community_favorites doc, aggregate a star-count per seed, and
## emit community_favorites_loaded with an array of {seed, star_count} sorted by
## star_count DESC (ties are shuffled by the view, not here).
func get_community_favorites() -> void:
	print("[LeaderboardService] get_community_favorites")

	var cached = _cache_get(CACHE_KEY_COMMUNITY)
	if cached != null:
		emit_signal("community_favorites_loaded", cached, true, "")
		return

	var url := BASE_URL + ":runQuery"
	var payload := {
		"structuredQuery": {
			"from": [ { "collectionId": "community_favorites" } ],
			"limit": 500
		}
	}
	_http_request(url, HTTPClient.METHOD_POST, PackedStringArray(), JSON.stringify(payload), func(result: int, code: int, headers: PackedStringArray, res_body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS:
			print("[LeaderboardService] get_community_favorites FAILED: HTTP connection error")
			emit_signal("community_favorites_loaded", [], false, "HTTP connection error")
			return
		if code != 200:
			print("[LeaderboardService] get_community_favorites FAILED: HTTP ", code)
			emit_signal("community_favorites_loaded", [], false, "Server returned error: HTTP " + str(code))
			return

		var json = JSON.parse_string(res_body.get_string_from_utf8())
		var counts: Dictionary = {}
		if json is Array:
			for item in json:
				if not (item is Dictionary and item.has("document")): continue
				var doc = item["document"]
				if not (doc is Dictionary and doc.has("fields")): continue
				var seeds = _parse_firestore_value({ "mapValue": { "fields": doc["fields"] } }).get("seeds", [])
				if not seeds is Array: continue
				# Dedupe within a single player's doc so one player = one star.
				var seen := {}
				for s in seeds:
					var code_str := str(s).strip_edges()
					if code_str == "" or seen.has(code_str): continue
					seen[code_str] = true
					counts[code_str] = int(counts.get(code_str, 0)) + 1

		var list: Array = []
		for seed_code in counts.keys():
			list.append({ "seed": seed_code, "star_count": int(counts[seed_code]) })
		list.sort_custom(func(a, b):
			return int(a.get("star_count", 0)) > int(b.get("star_count", 0))
		)

		print("[LeaderboardService] get_community_favorites OK: ", list.size(), " seeds")
		_cache_set(CACHE_KEY_COMMUNITY, list)
		emit_signal("community_favorites_loaded", list, true, "")
	)
