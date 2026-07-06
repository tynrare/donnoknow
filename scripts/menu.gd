extends Control

func _ready() -> void:
	$CenterContainer/VBox/Play.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/play.tscn"))
