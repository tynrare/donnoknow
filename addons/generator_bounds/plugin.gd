# agent: composer-2.5 | 2026-07-08 | generator bounds gizmo | g7h8i9
@tool
extends EditorPlugin

const PROCEDURAL_SCRIPT := "res://scripts/generator/procedural_tilemap.gd"
const MIN_SIZE := Vector2i(1, 1)

enum Handle {
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_RIGHT,
	BOTTOM_LEFT,
	TOP,
	RIGHT,
	BOTTOM,
	LEFT,
	CENTER,
}

enum DragMode { NONE, MOVE, RESIZE }

var _drag_mode := DragMode.NONE
var _active_handle := Handle.CENTER
var _start_bounds := Rect2i()
var _start_mouse_tile := Vector2i()
var _target: TileMapLayer = null


func _edit(object: Object) -> void:
	if object is TileMapLayer and _is_procedural_layer(object):
		(object as TileMapLayer).queue_redraw()


func _handles(object: Object) -> bool:
	return _is_procedural_layer(object)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	var node := _selected_layer()
	if node == null:
		_reset_drag()
		return false

	var canvas_pos := _mouse_canvas_pos(event)
	if canvas_pos.x == INF:
		return false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			var local_pos: Vector2 = node.to_local(canvas_pos)
			var handle := _pick_handle(node, local_pos)
			if handle < 0:
				_reset_drag()
				return false
			_target = node
			_active_handle = handle
			_start_bounds = node.bounds
			_start_mouse_tile = node.canvas_pos_to_bounds_tile(canvas_pos)
			_drag_mode = DragMode.MOVE if handle == Handle.CENTER else DragMode.RESIZE
			return true

		if _drag_mode != DragMode.NONE and _target == node:
			_commit_bounds(node, _start_bounds, node.bounds)
			_reset_drag()
			node.queue_bounds_redraw()
			return true

	elif event is InputEventMouseMotion and _drag_mode != DragMode.NONE and _target == node:
		var tile: Vector2i = node.canvas_pos_to_bounds_tile(canvas_pos)
		var next := _snap_bounds(
			_compute_bounds(_start_bounds, _start_mouse_tile, tile, _active_handle)
		)
		if next != node.bounds:
			node.bounds = next
			node.queue_bounds_redraw()
		return true

	return false


func _is_procedural_layer(object: Object) -> bool:
	if object == null or not object.get_script():
		return false
	return object.get_script().resource_path == PROCEDURAL_SCRIPT


func _selected_layer() -> TileMapLayer:
	var sel := get_editor_interface().get_selection().get_selected_nodes()
	if sel.is_empty():
		return null
	var node: Node = sel[0]
	if _is_procedural_layer(node):
		return node as TileMapLayer
	return null


func _mouse_canvas_pos(event: InputEvent) -> Vector2:
	if not (event is InputEventMouse):
		return Vector2(INF, INF)
	var vp := get_editor_interface().get_editor_viewport_2d()
	return vp.get_global_canvas_transform().affine_inverse() * (event as InputEventMouse).position


func _pick_handle(node: TileMapLayer, local_pos: Vector2) -> int:
	var rect: Rect2 = node.get_bounds_local_rect()
	var hit: float = node.BOUNDS_HANDLE_RADIUS

	var points: Array[Vector2] = [
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
		rect.position + Vector2(rect.size.x * 0.5, 0.0),
		rect.position + Vector2(rect.size.x, rect.size.y * 0.5),
		rect.position + Vector2(rect.size.x * 0.5, rect.size.y),
		rect.position + Vector2(0.0, rect.size.y * 0.5),
		rect.get_center(),
	]
	for i in points.size():
		if local_pos.distance_to(points[i]) <= hit:
			return i
	return -1


func _snap_bounds(rect: Rect2i) -> Rect2i:
	var pos := rect.position
	var end := rect.position + rect.size - Vector2i.ONE
	if end.x < pos.x:
		end.x = pos.x
	if end.y < pos.y:
		end.y = pos.y
	var size := end - pos + Vector2i.ONE
	size.x = maxi(size.x, MIN_SIZE.x)
	size.y = maxi(size.y, MIN_SIZE.y)
	return Rect2i(pos, size)


func _compute_bounds(
	start: Rect2i,
	start_tile: Vector2i,
	current_tile: Vector2i,
	handle: Handle,
) -> Rect2i:
	var pos := start.position
	var end := start.position + start.size - Vector2i.ONE

	match handle:
		Handle.CENTER:
			return Rect2i(start.position + current_tile - start_tile, start.size)
		Handle.TOP_LEFT:
			pos = Vector2i(mini(current_tile.x, end.x), mini(current_tile.y, end.y))
		Handle.TOP_RIGHT:
			pos.y = mini(current_tile.y, end.y)
			end.x = maxi(current_tile.x, pos.x)
		Handle.BOTTOM_RIGHT:
			end = Vector2i(maxi(current_tile.x, pos.x), maxi(current_tile.y, pos.y))
		Handle.BOTTOM_LEFT:
			pos.x = mini(current_tile.x, end.x)
			end.y = maxi(current_tile.y, pos.y)
		Handle.TOP:
			pos.y = mini(current_tile.y, end.y)
		Handle.RIGHT:
			end.x = maxi(current_tile.x, pos.x)
		Handle.BOTTOM:
			end.y = maxi(current_tile.y, pos.y)
		Handle.LEFT:
			pos.x = mini(current_tile.x, end.x)

	return Rect2i(pos, end - pos + Vector2i.ONE)


func _commit_bounds(node: TileMapLayer, before: Rect2i, after: Rect2i) -> void:
	if before == after:
		return
	var ur := get_undo_redo()
	ur.create_action("Set generation bounds", UndoRedo.MERGE_DISABLE, node)
	ur.add_do_property(node, "bounds", after)
	ur.add_undo_property(node, "bounds", before)
	ur.commit_action()


func _reset_drag() -> void:
	_drag_mode = DragMode.NONE
	_target = null
