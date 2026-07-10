# agent: composer-2.5 | 2026-07-10 | platform drop through | 4cbe92
extends CharacterBody2D

# agent: composer-2.5 | 2026-07-10 | export move jump vars | 48814b
@export var move_speed: float = 80.0
@export var jump_velocity: float = -180.0
@export var wall_slide_speed: float = 60.0
@export var wall_jump_normal_scale: float = 0.2
@export var wall_jump_lock_time: float = 0.15

const GRAVITY := 600.0
const PLATFORM_LAYER := 2
const PLATFORM_PHYSICS_LAYER := 1
const CLIMB_SPEED_SCALE := 0.5

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D

var _drop_active := false
var _on_ladder := false
var _wall_jump_lock := 0.0


func _physics_process(delta: float) -> void:
	var near_ladder := _touching_ladder()
	_on_ladder = near_ladder
	ControlsBridge.set_on_ladder(_on_ladder)

	var move_x := ControlsBridge.move_x()
	if move_x != 0.0:
		_sprite.flip_h = move_x < 0.0

	if _on_ladder:
		_move_on_ladder(move_x)
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta
		if is_on_wall():
			velocity.y = minf(velocity.y, wall_slide_speed)

	if _wall_jump_lock > 0.0:
		_wall_jump_lock -= delta

	var on_platform := _is_on_one_way_platform()
	ControlsBridge.set_on_platform(on_platform)

	# agent: composer-2.5 | 2026-07-10 | drop no velocity impulse | 44451b
	if ControlsBridge.is_pressed("down") and on_platform:
		_drop_active = true

	if _drop_active:
		set_collision_mask_value(PLATFORM_LAYER, false)
		if not ControlsBridge.is_pressed("down"):
			_drop_active = false
	else:
		set_collision_mask_value(PLATFORM_LAYER, true)

	# agent: composer-2.5 | 2026-07-10 | ground jump on press only | 920602
	if ControlsBridge.just_pressed("jump") and is_on_wall() and not is_on_floor() and not _drop_active:
		var push := _wall_push_normal()
		if push != Vector2.ZERO:
			velocity.x = push.x * absf(jump_velocity) * wall_jump_normal_scale
			velocity.y = jump_velocity
			position += Vector2(push.x * 2.0, 0.0)
			_wall_jump_lock = wall_jump_lock_time
	elif ControlsBridge.just_pressed("jump") and is_on_floor() and not _drop_active:
		velocity.y = jump_velocity

	if _wall_jump_lock <= 0.0:
		velocity.x = move_x * move_speed

	if ControlsBridge.just_pressed("attack"):
		_attack()

	move_and_slide()


func _attack() -> void:
	pass


func _wall_push_normal() -> Vector2:
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if absf(n.x) > absf(n.y):
			return Vector2(signf(n.x), 0.0)
	var wn := get_wall_normal()
	if absf(wn.x) > 0.1:
		return Vector2(signf(wn.x), 0.0)
	return Vector2.ZERO


# agent: composer-2.5 | 2026-07-10 | auto ladder no gravity | 7db6ce
func _move_on_ladder(move_x: float) -> void:
	velocity.x = move_x * move_speed
	var climb := move_speed * CLIMB_SPEED_SCALE
	if ControlsBridge.is_pressed("jump"):
		velocity.y = -climb
	elif ControlsBridge.is_pressed("down"):
		velocity.y = climb
	else:
		velocity.y = 0.0


func _touching_ladder() -> bool:
	for tilemap in _relevant_tilemaps():
		for offset in _body_offsets():
			if _cell_is_ladder(tilemap, _world_to_cell(tilemap, global_position + offset)):
				return true
	return false


func _cell_is_ladder(tilemap: TileMapLayer, cell: Vector2i) -> bool:
	var data := tilemap.get_cell_tile_data(cell)
	return data != null and data.get_custom_data("ladder") == true


# agent: composer-2.5 | 2026-07-10 | foot probe platform detect | 2615c6
func _is_on_one_way_platform() -> bool:
	if not is_on_floor():
		return false
	for tilemap in _relevant_tilemaps():
		for offset in _foot_offsets():
			if _probe_one_way(tilemap, global_position + offset):
				return true
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y > -0.5:
			continue
		var collider = col.get_collider()
		if collider is TileMapLayer and _probe_one_way(collider, col.get_position()):
			return true
	return false


func _relevant_tilemaps() -> Array[TileMapLayer]:
	var root := get_parent()
	if root == null:
		return []
	var maps: Array[TileMapLayer] = []
	for node in root.find_children("", "TileMapLayer", true):
		maps.append(node)
	return maps


func _world_to_cell(tilemap: TileMapLayer, world_pos: Vector2) -> Vector2i:
	return tilemap.local_to_map(tilemap.to_local(world_pos))


func _body_offsets() -> Array[Vector2]:
	var rect := (_collision.shape as RectangleShape2D).size
	var half := rect * 0.5
	var cx := _collision.position.x
	var cy := _collision.position.y
	return [
		Vector2(cx, cy),
		Vector2(cx, cy - half.y + 0.5),
		Vector2(cx, cy + half.y - 0.5),
	]


func _foot_offsets() -> Array[Vector2]:
	var rect := (_collision.shape as RectangleShape2D).size
	var half := rect * 0.5
	var cx := _collision.position.x
	var foot_y := _collision.position.y + half.y - 0.5
	var inset_x := half.x - 0.5
	return [
		Vector2(cx - inset_x, foot_y),
		Vector2(cx, foot_y),
		Vector2(cx + inset_x, foot_y),
	]


func _probe_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell,
		cell + Vector2i(-1, 0),
		cell + Vector2i(1, 0),
		cell + Vector2i(0, -1),
	]


func _probe_one_way(tilemap: TileMapLayer, world_pos: Vector2) -> bool:
	for c in _probe_neighbors(_world_to_cell(tilemap, world_pos)):
		if _cell_one_way_at(tilemap, c):
			return true
	return false


func _cell_one_way_at(tilemap: TileMapLayer, cell: Vector2i) -> bool:
	var data := tilemap.get_cell_tile_data(cell)
	if data == null:
		return false
	if data.get_collision_polygons_count(PLATFORM_PHYSICS_LAYER) == 0:
		return false
	for i in data.get_collision_polygons_count(PLATFORM_PHYSICS_LAYER):
		if data.is_collision_polygon_one_way(PLATFORM_PHYSICS_LAYER, i):
			return true
	return false
