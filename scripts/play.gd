# agent: composer-2.5 | 2026-07-07 | camera view extend | 2f75e8
extends Node2D

@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	get_tree().root.size_changed.connect(_center_camera)
	call_deferred("_center_camera")


func _center_camera() -> void:
	_camera.position = Vector2(get_tree().root.content_scale_size) / 2.0
