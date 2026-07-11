# agent: composer-2.5 | 2026-07-11 | playbtn hover api | c071d0
extends Node3D

@export var hover_scale := 1.12
@export var scale_speed := 8.0

@onready var _playbtn: Node3D = $playbtn

var _target_scale := 1.0


func _process(delta: float) -> void:
	var next := lerpf(_playbtn.scale.x, _target_scale, scale_speed * delta)
	_playbtn.scale = Vector3.ONE * next


func set_playbtn_hover(hovering: bool) -> void:
	_target_scale = hover_scale if hovering else 1.0
