extends Control


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	ScreenNavigator.start_target = "home"
	ScreenNavigator.start_level = 0
	get_tree().change_scene_to_file("res://screens/main.tscn")
