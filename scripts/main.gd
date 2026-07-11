# agent: composer-2.5 | 2026-07-11 | fix null world3d raycast | 9e3349
extends Control

const PLAY_SCENE := "res://scenes/play.tscn"

@onready var _container: SubViewportContainer = $MenuSplash
@onready var _viewport: SubViewport = $MenuSplash/SubViewport

var _title: Node3D
var _camera: Camera3D
var _playbtn_area: Area3D
var _hovering := false


func _ready() -> void:
	_container.mouse_filter = MOUSE_FILTER_STOP
	_viewport.handle_input_locally = false
	_container.gui_input.connect(_on_container_gui_input)
	_container.mouse_exited.connect(func() -> void: _set_hover(false))

	var splash := _viewport.get_node("Splash")
	_title = splash.get_node("title")
	_camera = splash.get_node("Camera3D")
	_playbtn_area = _title.get_node("playbtn/PlayBtnArea")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_set_hover(false)


func _on_container_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return

	var vp_pos := _map_mouse_to_viewport()
	var on_btn := _raycast_playbtn(vp_pos)

	if event is InputEventMouseMotion:
		_set_hover(on_btn)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and on_btn:
		_container.accept_event()
		get_tree().change_scene_to_file(PLAY_SCENE)


func _map_mouse_to_viewport() -> Vector2:
	var local := _container.get_local_mouse_position()
	var size := _container.size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2(-1.0, -1.0)
	return local * (Vector2(_viewport.size) / size)


func _raycast_playbtn(vp_pos: Vector2) -> bool:
	var world := _camera.get_world_3d()
	if world == null:
		return false
	var from := _camera.project_ray_origin(vp_pos)
	var to := from + _camera.project_ray_normal(vp_pos) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := world.direct_space_state.intersect_ray(query)
	return hit.get("collider") == _playbtn_area


func _set_hover(on: bool) -> void:
	if on == _hovering:
		return
	_hovering = on
	_title.set_playbtn_hover(on)
