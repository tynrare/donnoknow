# agent: composer-2.5 | 2026-07-07 | manifest grid 24 cols | f8a9b0
extends RefCounted

const GenWfc := preload("res://scripts/generator/wfc.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const GenTmx := preload("res://scripts/generator/tmx.gd")
const GenValidate := preload("res://scripts/generator/validate.gd")

const DEFAULT_MANIFEST := "res://assets/tiles/adve/manifest.json"
const TILED_GID_MASK := 0x1FFFFFFF


static func default_options() -> Dictionary:
	return {
		"repeat_penalty": 1.0,
	}


static func load_manifest(path: String = DEFAULT_MANIFEST) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func columns(manifest: Dictionary) -> int:
	return int(manifest.get("columns", 0))


static func rows(manifest: Dictionary) -> int:
	return int(manifest.get("rows", 0))


static func tile_count(manifest: Dictionary) -> int:
	if manifest.has("tile_count"):
		return int(manifest.tile_count)
	var cols: int = columns(manifest)
	var row_count: int = rows(manifest)
	if cols > 0 and row_count > 0:
		return cols * row_count
	return 0


static func map_size(manifest: Dictionary) -> Vector2i:
	var w: int = int(manifest.get("map_width", 0))
	var h: int = int(manifest.get("map_height", 0))
	if w > 0 and h > 0:
		return Vector2i(w, h)
	var maps: Array = manifest.get("maps", [])
	if not maps.is_empty():
		return GenTmx.read_map_size(str(maps[0]))
	return Vector2i(0, 0)


static func gid_to_local(manifest: Dictionary, gid: int) -> int:
	return normalize_gid(gid) - int(manifest.get("first_gid", 1))


static func local_to_gid(manifest: Dictionary, local: int) -> int:
	return int(manifest.get("first_gid", 1)) + local


static func atlas_to_local(manifest: Dictionary, atlas: Vector2i) -> int:
	var cols: int = columns(manifest)
	if cols <= 0:
		return -1
	return atlas.y * cols + atlas.x


static func local_to_atlas(manifest: Dictionary, local: int) -> Vector2i:
	var cols: int = columns(manifest)
	if cols <= 0 or local < 0:
		return Vector2i(-1, -1)
	return Vector2i(local % cols, local / cols)


static func normalize_gid(raw: int) -> int:
	return raw & TILED_GID_MASK


static func is_valid_gid(manifest: Dictionary, gid: int) -> bool:
	var local := gid_to_local(manifest, gid)
	return local >= 0 and local < tile_count(manifest)


static func gid_to_atlas(manifest: Dictionary, gid: int) -> Vector2i:
	if not is_valid_gid(manifest, gid):
		return Vector2i(-1, -1)
	return local_to_atlas(manifest, gid_to_local(manifest, gid))


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


static func paint_cell(
	layer: TileMapLayer,
	manifest: Dictionary,
	bounds: Rect2i,
	width: int,
	idx: int,
	gid: int,
	constraints: Dictionary,
) -> void:
	if constraints.has("modes"):
		match constraints.modes[idx]:
			GenConstraints.Mode.FIXED:
				return
			GenConstraints.Mode.FORBID:
				layer.erase_cell(bounds.position + Vector2i(idx % width, idx / width))
				return
	var cell := bounds.position + Vector2i(idx % width, idx / width)
	if gid <= 0:
		layer.erase_cell(cell)
		return
	var atlas := gid_to_atlas(manifest, gid)
	if atlas.x < 0:
		return
	layer.set_cell(cell, manifest.get("source_id", 0), atlas)


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
	var cols: int = columns(manifest)
	if cols <= 0:
		return out
	for y in height:
		for x in width:
			var atlas := layer.get_cell_atlas_coords(origin + Vector2i(x, y))
			if atlas.x < 0:
				continue
			out[y * width + x] = first_gid + atlas.y * cols + atlas.x
	return out


static func validate_manifest(manifest: Dictionary) -> String:
	return GenValidate.first_error(GenValidate.validate_setup(manifest))


static func validate_rules_grid(manifest: Dictionary, rules: Dictionary) -> String:
	var report := GenValidate.validate_setup(manifest, rules)
	return GenValidate.first_error(report)


static func validate_setup(
	manifest: Dictionary,
	rules: Dictionary = {},
	constraints: Dictionary = {},
) -> Dictionary:
	return GenValidate.validate_setup(manifest, rules, constraints)


static func format_report(report: Dictionary) -> String:
	return GenValidate.format_report(report)


static func generate(
	manifest: Dictionary,
	rules: Dictionary,
	constraints: Dictionary,
	seed: int = 0,
	options: Dictionary = {},
) -> Dictionary:
	var opts := default_options()
	for key in options:
		opts[key] = options[key]

	var err: String = validate_manifest(manifest)
	if not err.is_empty():
		return {"ok": false, "error": err}

	err = validate_rules_grid(manifest, rules)
	if not err.is_empty():
		return {"ok": false, "error": err}

	return GenWfc.generate(rules, constraints, seed, manifest, opts)


static func create_job(
	manifest: Dictionary,
	rules: Dictionary,
	constraints: Dictionary,
	seed: int = 0,
	options: Dictionary = {},
) -> GenWfcJob:
	var opts := default_options()
	for key in options:
		opts[key] = options[key]
	return GenWfcJob.new(rules, constraints, manifest, seed, opts)


static func finalize_job(
	job: GenWfcJob,
	rules: Dictionary,
	constraints: Dictionary,
	seed: int,
	manifest: Dictionary,
	options: Dictionary = {},
) -> Dictionary:
	var step := {
		"ok": not job.cancelled,
		"gids": job.out,
		"seed": job.base_seed,
		"method": "wfc_partial",
		"cancelled": job.cancelled,
	}
	return GenWfc._finalize_result(step, rules, constraints, seed, manifest, options)


static func analyze_manifest(manifest: Dictionary) -> Dictionary:
	var maps: Array = manifest.get("maps", [])
	var analyze: Dictionary = manifest.get("analyze", {})
	var min_adj: int = maxi(int(analyze.get("min_adj_count", 1)), 1)
	return GenRules.analyze_maps(maps, min_adj, manifest)


static func save_rules(manifest: Dictionary, rules: Dictionary) -> Error:
	var path: String = manifest.get("rules", "")
	if path.is_empty():
		return ERR_FILE_NOT_FOUND
	return GenRules.save(path, rules)
