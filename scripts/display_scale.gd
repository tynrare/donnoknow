# agent: composer-2.5 | 2026-07-07 | 16:9 scale cap | f074bd
extends Node

const BASE := Vector2i(640, 360)
const ASPECT := 16.0 / 9.0


func _ready() -> void:
	get_tree().root.size_changed.connect(_apply)
	call_deferred("_apply")


func _apply() -> void:
	var root := get_tree().root
	var win := root.size
	if win.y <= 0 or win.x <= 0:
		return

	var aspect := float(win.x) / float(win.y)
	var scale: float
	var design: Vector2i

	if aspect >= ASPECT:
		scale = float(win.y) / BASE.y
		design = Vector2i(roundi(win.x / scale), BASE.y)
	else:
		scale = float(win.x) / BASE.x
		design = Vector2i(BASE.x, roundi(win.y / scale))

	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_factor = scale
	root.content_scale_size = design
