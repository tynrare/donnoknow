extends RefCounted

const GenWfc := preload("res://scripts/generator/wfc.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")

const DEFAULT_MANIFEST := "res://assets/tiles/adve/manifest.json"
const TILED_GID_MASK := 0x1FFFFFFF


static func load_manifest(path: String = DEFAULT_MANIFEST) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func tile_count(manifest: Dictionary) -> int:
	if manifest.has("tile_count"):
		return int(manifest.tile_count)
	var cols: int = manifest.get("columns", 16)
	var rows: int = manifest.get("rows", 16)
	return cols * rows


static func normalize_gid(raw: int) -> int:
	return raw & TILED_GID_MASK


static func is_valid_gid(manifest: Dictionary, gid: int) -> bool:
	var first_gid: int = manifest.get("first_gid", 1)
	var local := normalize_gid(gid) - first_gid
	return local >= 0 and local < tile_count(manifest)


static func gid_to_atlas(manifest: Dictionary, gid: int) -> Vector2i:
	if not is_valid_gid(manifest, gid):
		return Vector2i(-1, -1)
	var first_gid: int = manifest.get("first_gid", 1)
	var cols: int = manifest.get("columns", 16)
	var local := normalize_gid(gid) - first_gid
	return Vector2i(local % cols, local / cols)


static func apply_to_layer(layer: TileMapLayer, manifest: Dictionary, gids: PackedInt32Array, width: int) -> void:
	layer.clear()
	_apply_gids(layer, manifest, gids, width, Vector2i.ZERO, GenConstraints.empty(width, gids.size() / width))


static func apply_merge(
	layer: TileMapLayer,
	manifest: Dictionary,
	gids: PackedInt32Array,
	constraints: Dictionary,
	bounds: Rect2i,
) -> void:
	_apply_gids(layer, manifest, gids, bounds.size.x, bounds.position, constraints)


static func clear_bounds(layer: TileMapLayer, bounds: Rect2i) -> void:
	for y in bounds.size.y:
		for x in bounds.size.x:
			layer.erase_cell(bounds.position + Vector2i(x, y))


static func _apply_gids(
	layer: TileMapLayer,
	manifest: Dictionary,
	gids: PackedInt32Array,
	width: int,
	origin: Vector2i,
	constraints: Dictionary,
) -> void:
	var source_id: int = manifest.get("source_id", 0)
	var has_constraints := constraints.has("modes")
	for i in gids.size():
		var cell := origin + Vector2i(i % width, i / width)
		if has_constraints:
			match constraints.modes[i]:
				GenConstraints.Mode.FIXED:
					continue
				GenConstraints.Mode.FORBID:
					layer.erase_cell(cell)
					continue
		var gid := gids[i]
		if gid <= 0:
			layer.erase_cell(cell)
			continue
		var atlas := gid_to_atlas(manifest, gid)
		if atlas.x < 0:
			continue
		layer.set_cell(cell, source_id, atlas)


static func gids_from_layer(
	layer: TileMapLayer,
	manifest: Dictionary,
	width: int,
	height: int,
	origin: Vector2i = Vector2i.ZERO,
) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(width * height)
	out.fill(0)
	var first_gid: int = manifest.get("first_gid", 1)
	var cols: int = manifest.get("columns", 16)
	for y in height:
		for x in width:
			var atlas := layer.get_cell_atlas_coords(origin + Vector2i(x, y))
			if atlas.x < 0:
				continue
			out[y * width + x] = first_gid + atlas.y * cols + atlas.x
	return out


static func generate(
	manifest: Dictionary,
	rules: Dictionary,
	constraints: Dictionary,
	seed: int = 0,
) -> Dictionary:
	return GenWfc.generate(rules, constraints, seed, manifest)


static func analyze_manifest(manifest: Dictionary) -> Dictionary:
	var maps: Array = manifest.get("maps", [])
	return GenRules.analyze_maps(maps, 1, manifest)


static func save_rules(manifest: Dictionary, rules: Dictionary) -> Error:
	var path: String = manifest.get("rules", "")
	if path.is_empty():
		return ERR_FILE_NOT_FOUND
	return GenRules.save(path, rules)
