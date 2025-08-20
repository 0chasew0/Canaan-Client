extends Control

func _ready():
	pass
	

func _on_canaan_singleplayer_pressed() -> void:
	# Load a singleplayer game.
	
	get_tree().change_scene_to_file("res://scenes/canaan.tscn")
