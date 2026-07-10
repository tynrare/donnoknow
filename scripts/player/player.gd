# agent: composer-2.5 | 2026-07-10 | platform drop through | 4cbe92
extends CharacterBody2D

# agent: composer-2.5 | 2026-07-10 | export move jump vars | 48814b
@export var move_speed: float = 80.0
@export var jump_velocity: float = -180.0
@export var wall_slide_speed: float = 60.0
@export var wall_jump_normal_scale: float = 0.2
@export var wall_jump_input_cooldown: float = 0.12

const GRAVITY := 600.0
const PLATFORM_LAYER := 2
const PLATFORM_PHYSICS_LAYER := 1
const CLIMB_SPEED_SCALE := 0.5
const DROP_GRACE_TIME := 0.08
const DROP_CLEAR_MARGIN := 2.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D

var _drop_active := false
var _drop_tilemap: TileMapLayer = null
var _drop_cell := Vector2i.ZERO
var _drop_grace := 0.0
var _on_ladder := false
var _wall_jump_cooldown := 0.0
var _wall_away_dir := 0.0


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
		if is_on_wall() and _wall_jump_cooldown <= 0.0:
			velocity.y = minf(velocity.y, wall_slide_speed)

	if _wall_jump_cooldown > 0.0:
		_wall_jump_cooldown -= delta

	var on_platform := _is_on_one_way_platform()
	ControlsBridge.set_on_platform(on_platform)

	# agent: composer-2.5 | 2026-07-10 | drop single platform fix | 001845
	if ControlsBridge.is_pressed("down") and on_platform and not _drop_active:
		var platform := _find_platform_under_feet()
		if not platform.is_empty():
			_drop_active = true
			_drop_tilemap = platform.tilemap
			_drop_cell = platform.cell
			_drop_grace = DROP_GRACE_TIME

	if _drop_active:
		set_collision_mask_value(PLATFORM_LAYER, false)
		_drop_grace -= delta
		if not ControlsBridge.is_pressed("down") or (_drop_grace <= 0.0 and _cleared_drop_platform()):
			_drop_active = false
			_drop_tilemap = null
	else:
		set_collision_mask_value(PLATFORM_LAYER, true)

	var wall_jumped := false
	if ControlsBridge.just_pressed("jump") and is_on_wall() and not is_on_floor() and not _drop_active:
		var push := _wall_push_normal()
		if push != Vector2.ZERO:
			_wall_away_dir = push.x
			velocity.y = jump_velocity
			velocity.x = push.x * absf(jump_velocity) * wall_jump_normal_scale
			_wall_jump_cooldown = wall_jump_input_cooldown
			wall_jumped = true
	elif ControlsBridge.just_pressed("jump") and is_on_floor() and not _drop_active:
		velocity.y = jump_velocity

	if not wall_jumped:
		_apply_horizontal(move_x)

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


func _apply_horizontal(move_x: float) -> void:
	if _wall_jump_cooldown > 0.0:
		if move_x != 0.0 and signf(move_x) == signf(_wall_away_dir):
			velocity.x = move_x * move_speed
		return
	velocity.x = move_x * move_speed


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


func _find_platform_under_feet() -> Dictionary:
	var best := {}
	var best_top := -INF
	for tilemap in _relevant_tilemaps():
		for offset in _foot_offsets():
			var cell := _world_to_cell(tilemap, global_position + offset)
			if _cell_one_way_at(tilemap, cell):
				var top_y := _platform_top_y(tilemap, cell)
				if top_y > best_top:
					best_top = top_y
					best = { "tilemap": tilemap, "cell": cell }
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y > -0.5:
			continue
		var collider = col.get_collider()
		if collider is TileMapLayer:
			var cell := _world_to_cell(collider, col.get_position())
			if _cell_one_way_at(collider, cell):
				var top_y := _platform_top_y(collider, cell)
				if top_y > best_top:
					best_top = top_y
					best = { "tilemap": collider, "cell": cell }
	return best


func _cleared_drop_platform() -> bool:
	if _drop_tilemap == null:
		return true
	return _foot_global_y() > _platform_top_y(_drop_tilemap, _drop_cell) + DROP_CLEAR_MARGIN


func _platform_top_y(tilemap: TileMapLayer, cell: Vector2i) -> float:
	return tilemap.to_global(tilemap.map_to_local(cell)).y


func _foot_global_y() -> float:
	var rect := (_collision.shape as RectangleShape2D).size
	return global_position.y + _collision.position.y + rect.y * 0.5 - 0.5
