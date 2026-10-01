extends SceneTree

func _init() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("--- FIRESTORE LEADERBOARD TEST RUN ---")
	
	var rootv = Node.new()
	var root_node = root
	# Add root to tree so HTTPRequest nodes can be added to the scene tree
	root_node.add_child(rootv)
	
	var global_script = load("res://global.gd")
	var Global_node = global_script.new()
	Global_node.name = "Global"
	root.add_child(Global_node)
	# Set global singleton reference since autoload isn't active in raw scripts
	# But wait, Global is a class name or a global constant. In GDScript, Global is the autoload.
	# Let's see if we can just define Global in the local script or if we need to mock it.
	# Actually, autoloads are registered in project.godot, but when running `godot -s`, autoloads are NOT loaded automatically!
	# So we need to put it on root.
	
	var skills_db_script = load("res://skills_db.gd")
	var SkillsDB_node = skills_db_script.new()
	SkillsDB_node.name = "SkillsDB"
	root.add_child(SkillsDB_node)
	
	var service_script = load("res://leaderboard_service.gd")
	var LeaderboardService_node = service_script.new()
	LeaderboardService_node.name = "LeaderboardService"
	root.add_child(LeaderboardService_node)
	
	print("[Test] Autoloads mocked on scene tree.")
	
	# Fetch Hall of Fame
	print("[Test] Fetching Global Hall of Fame...")
	LeaderboardService_node.hall_of_fame_loaded.connect(func(hof, success, err):
		print("[Test] Global HOF Loaded. Success: ", success, " Error: ", err)
		print("[Test] HOF Data: ", hof)
		
		# Fetch Level Leaderboard
		print("[Test] Fetching level leaderboard for test seed 'test'...")
		LeaderboardService_node.level_leaderboard_loaded.connect(func(seed_val, stat, results, success2, err2):
			print("[Test] Level Leaderboard Loaded. Seed: ", seed_val, " Stat: ", stat, " Success: ", success2, " Error: ", err2)
			print("[Test] Results: ", results)
			
			# Submit Result
			print("[Test] Submitting level result for 'test'...")
			LeaderboardService_node.submit_result_completed.connect(func(success3, err3):
				print("[Test] Submit Result Completed. Success: ", success3, " Error: ", err3)
				print("--- TEST COMPLETE ---")
				root.queue_free()
				quit()
			)
			LeaderboardService_node.submit_level_result("test", "test_player_id", "TestPlayer", 120, 80, 8)
		)
		LeaderboardService_node.get_level_leaderboard("test", "best_score")
	)
	LeaderboardService_node.get_hall_of_fame()
