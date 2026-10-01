extends Node

## Entry-point router. If the player has unlocked the UI, send them to the
## main menu. Otherwise show the tutorial (first-time only) then drop them
## straight into the level so their first run triggers the "buy UI" prompt.

func _ready() -> void:
	call_deferred("_route")

func _route() -> void:
	if Global.is_unlocked("ui"):
		get_tree().change_scene_to_file("res://main_menu.tscn")
	else:
		get_tree().change_scene_to_file("res://leve.tscn")
