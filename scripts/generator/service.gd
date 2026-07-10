# agent: composer-2.5 | 2026-07-07 | manifest grid 24 cols | f8a9b0
extends RefCounted

const GenStitch := preload("res://scripts/generator/stitch.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenTmx := preload("res://scripts/generator/tmx.gd")
const GenValidate := preload("res://scripts/generator/validate.gd")

const _WFC_SCRIPT := "res://scripts/generator/wfc.gd"
const _WFC_JOB_SCRIPT := "res://scripts/generator/wfc_job.gd"


static func _wfc():
	return load(_WFC_SCRIPT)


static func _wfc_job():
	return load(_WFC_JOB_SCRIPT)

const DEFAULT_MANIFEST := "res://assets/tiles/adve/manifest.json"
const TILED_GID_MASK := 0x1FFFFFFF


static func default_options() -> Dictionary:
	return {
		"gen_method": "wfc",
		"use_patterns": true,
		"pattern_propagate": false,
		"backtrack_depth": 8,
		"backtrack_incidents": 64,
		"backtrack_cells": 128,
		"max_restarts": 8,
		"tile_bias": {},
		"chunk_size": 8,
		"repeat_penalty": 1.0,
	}


static func load_manifest(path: String = DEFAULT_MANIFEST) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is not Dictionary:
		return {}
	return enrich_manifest(data)


# agent: composer-2.5 | 2026-07-10 | enrich manifest on load | 1ef750
static func enrich_manifest(manifest: Dictionary) -> Dictionary:
	if manifest.is_empty():
		return manifest
	var out: Dictionary = manifest.duplicate(true)
	if not out.has("first_gid"):
		out["first_gid"] = 1
	if not out.has("source_id"):
		out["source_id"] = 0
	if not out.has("background_gid"):
		out["background_gid"] = 1

	var tile_size: Array = out.get("tile_size", [])
	var tw: int = int(tile_size[0]) if tile_size.size() > 0 else 8
	var th: int = int(tile_size[1]) if tile_size.size() > 1 else 8
	var tsx: Dictionary = GenValidate.read_tsx_meta(GenValidate.tsx_path(out))
	if int(tsx.get("tilewidth", 0)) > 0:
		tw = int(tsx.tilewidth)
	if int(tsx.get("tileheight", 0)) > 0:
		th = int(tsx.tileheight)
	out["tile_size"] = [tw, th]

	if int(out.get("columns", 0)) <= 0:
		if int(tsx.get("columns", 0)) > 0:
			out["columns"] = int(tsx.columns)
		else:
			var img_size: Vector2i = GenValidate.atlas_image_size(out)
			if img_size.x > 0 and tw > 0:
				out["columns"] = img_size.x / tw

	if int(out.get("rows", 0)) <= 0:
		var cols: int = int(out.get("columns", 0))
		if int(tsx.get("tilecount", 0)) > 0 and cols > 0:
			out["rows"] = int(tsx.tilecount) / cols
		else:
			var img_size: Vector2i = GenValidate.atlas_image_size(out)
			if img_size.y > 0 and th > 0 and cols > 0:
				out["rows"] = img_size.y / th

	if int(out.get("tile_count", 0)) <= 0:
		var cols: int = int(out.get("columns", 0))
		var row_count: int = int(out.get("rows", 0))
		if cols > 0 and row_count > 0:
			out["tile_count"] = cols * row_count
		elif int(tsx.get("tilecount", 0)) > 0:
			out["tile_count"] = int(tsx.tilecount)

	if int(out.get("map_width", 0)) <= 0 or int(out.get("map_height", 0)) <= 0:
		var maps: Array = out.get("maps", [])
		if not maps.is_empty():
			var map_size: Vector2i = GenTmx.read_map_size(str(maps[0]))
			if map_size.x > 0:
				out["map_width"] = map_size.x
			if map_size.y > 0:
				out["map_height"] = map_size.y

	return out


static func resolve_train_scene(manifest: Dictionary, rules_path: String = "") -> String:
	var rules: String = rules_path if not rules_path.is_empty() else str(manifest.get("rules", ""))
	if rules.is_empty():
		return ""
	return train_scene_path(rules)


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


# agent: composer-2.5 | 2026-07-10 | composite gids train layer | 98127b
static func composite_gids(base: PackedInt32Array, overlay: PackedInt32Array) -> PackedInt32Array:
	var size: int = maxi(base.size(), overlay.size())
	var out := PackedInt32Array()
	out.resize(size)
	out.fill(0)
	for i in size:
		var b: int = base[i] if i < base.size() else 0
		var o: int = overlay[i] if i < overlay.size() else 0
		out[i] = o if o > 0 else b
	return out


static func apply_gids_region(
	layer: TileMapLayer,
	manifest: Dictionary,
	gids: PackedInt32Array,
	width: int,
	origin: Vector2i,
) -> void:
	var source_id: int = manifest.get("source_id", 0)
	for i in gids.size():
		var cell := origin + Vector2i(i % width, i / width)
		var gid: int = gids[i]
		if gid <= 0:
			layer.erase_cell(cell)
			continue
		var atlas := gid_to_atlas(manifest, gid)
		if atlas.x < 0:
			layer.erase_cell(cell)
			continue
		layer.set_cell(cell, source_id, atlas)


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
	max_restarts: int = 32,
	options: Dictionary = {},
) -> Dictionary:
	var opts := default_options()
	for key in options:
		opts[key] = options[key]
	if max_restarts == null:
		max_restarts = 32

	var err: String = validate_manifest(manifest)
	if not err.is_empty():
		return {"ok": false, "error": err}

	err = validate_rules_grid(manifest, rules)
	if not err.is_empty():
		return {"ok": false, "error": err}

	var method: String = str(opts.get("gen_method", "wfc"))
	if method == "chunk_stitch":
		return GenStitch.generate(rules, constraints, seed, manifest, opts)

	return _wfc().generate(rules, constraints, seed, manifest, max_restarts, opts)


static func create_job(
	manifest: Dictionary,
	rules: Dictionary,
	constraints: Dictionary,
	seed: int = 0,
	max_restarts: int = 32,
	options: Dictionary = {},
):
	if max_restarts == null:
		max_restarts = 32
	var opts := default_options()
	for key in options:
		opts[key] = options[key]
	return _wfc_job().new(rules, constraints, manifest, seed, max_restarts, opts)


static func finalize_job(
	job,
	rules: Dictionary,
	constraints: Dictionary,
	seed: int,
	manifest: Dictionary,
	options: Dictionary = {},
) -> Dictionary:
	var step := {
		"ok": not job.cancelled,
		"gids": job.out,
		"seed": job.base_seed + job.attempt - 1,
		"attempts": job.attempt,
		"backtracks": job.backtracks_used,
		"method": "wfc_partial",
		"cancelled": job.cancelled,
	}
	return _wfc()._finalize_result(step, rules, constraints, seed, manifest, options)


const TRAIN_ROOT_NAME := "TrainData"
const TRAIN_LAYER_NAME := "Tiles"


# agent: composer-2.5 | 2026-07-10 | train scene corpus flow | d4aa19
static func train_scene_path(rules_path: String) -> String:
	if rules_path.ends_with(".rules.json"):
		return rules_path.replace(".rules.json", ".train.tscn")
	return rules_path.get_basename() + ".train.tscn"


static func save_manifest(path: String, manifest: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(manifest, "\t"))
	return OK


# agent: composer-2.5 | 2026-07-10 | setup from tmx path | 79c0d1
static func setup_from_tmx(tmx_path: String) -> Dictionary:
	if tmx_path.is_empty() or not FileAccess.file_exists(tmx_path):
		return {"ok": false, "error": "missing tmx: %s" % tmx_path}

	var tmx_text := FileAccess.get_file_as_string(tmx_path)
	var tsx_src := _tmx_external_tileset_src(tmx_text)
	if tsx_src.is_empty():
		return {"ok": false, "error": "tmx has no external tileset source: %s" % tmx_path}

	var tmx_dir := tmx_path.get_base_dir()
	var tsx_path := tmx_dir.path_join(tsx_src)
	if not FileAccess.file_exists(tsx_path):
		return {"ok": false, "error": "missing tsx: %s" % tsx_path}

	var tsx_text := FileAccess.get_file_as_string(tsx_path)
	var atlas_rel := _tsx_image_source(tsx_text)
	if atlas_rel.is_empty():
		return {"ok": false, "error": "tsx has no image source: %s" % tsx_path}

	var atlas_path := tmx_dir.path_join(atlas_rel)
	if not FileAccess.file_exists(atlas_path):
		return {"ok": false, "error": "missing atlas: %s" % atlas_path}

	var tsx_meta := GenValidate.read_tsx_meta(tsx_path)
	var tw: int = maxi(int(tsx_meta.get("tilewidth", 8)), 1)
	var th: int = maxi(int(tsx_meta.get("tileheight", 8)), 1)
	var tile_size := Vector2i(tw, th)

	var pack: String = tmx_dir.get_file()
	if pack.is_empty():
		pack = tmx_path.get_file().get_basename()

	var tileset_path := "res://resources/%s.tileset.tres" % pack
	var rules_path := "res://resources/generator/%s.rules.json" % pack
	var manifest_path := tmx_dir.path_join("manifest.json")
	var tileset_src: String = tsx_src.get_file()

	var tileset := _create_tileset_from_atlas(atlas_path, tile_size)
	if tileset == null:
		return {"ok": false, "error": "failed to build tileset from %s" % atlas_path}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tileset_path.get_base_dir()))
	var ts_err: Error = ResourceSaver.save(tileset, tileset_path)
	if ts_err != OK:
		return {"ok": false, "error": "tileset save failed: %s" % error_string(ts_err)}

	var manifest := {
		"atlas": atlas_path,
		"background_gid": 1,
		"tileset": tileset_path,
		"tileset_src": tileset_src,
		"maps": [tmx_path],
		"rules": rules_path,
		"analyze": {"tileset_edges": true},
	}
	var man_err: Error = save_manifest(manifest_path, manifest)
	if man_err != OK:
		return {"ok": false, "error": "manifest save failed: %s" % error_string(man_err)}

	var enriched := enrich_manifest(manifest)
	var map_size := Vector2i(int(enriched.get("map_width", 0)), int(enriched.get("map_height", 0)))
	return {
		"ok": true,
		"manifest_path": manifest_path,
		"rules_path": rules_path,
		"tileset_path": tileset_path,
		"atlas_path": atlas_path,
		"map_size": map_size,
		"pack": pack,
	}


static func _tmx_external_tileset_src(tmx_text: String) -> String:
	var rx := RegEx.new()
	rx.compile("<tileset[^>]*source=\"([^\"]+)\"")
	var m := rx.search(tmx_text)
	return m.get_string(1) if m else ""


static func _tsx_image_source(tsx_text: String) -> String:
	var rx := RegEx.new()
	rx.compile("<image[^>]*source=\"([^\"]+)\"")
	var m := rx.search(tsx_text)
	return m.get_string(1) if m else ""


static func _create_tileset_from_atlas(atlas_path: String, tile_size: Vector2i) -> TileSet:
	var tex := load(atlas_path) as Texture2D
	if tex == null:
		return null
	var columns: int = tex.get_width() / tile_size.x
	var rows: int = tex.get_height() / tile_size.y
	if columns <= 0 or rows <= 0:
		return null

	var tileset := TileSet.new()
	tileset.tile_size = tile_size
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = tile_size
	tileset.add_source(src, 0)
	for y in rows:
		for x in columns:
			src.create_tile(Vector2i(x, y))
	return tileset


static func default_train_meta(chunk_size: Vector2i) -> Dictionary:
	return {
		"width": chunk_size.x,
		"height": chunk_size.y,
		"padding": 1,
		"next_x": 0,
		"next_y": 0,
		"chunks": [],
	}


static func ensure_train_scene(
	manifest: Dictionary,
	rules_path: String,
	tile_set: TileSet,
	chunk_size: Vector2i,
) -> Dictionary:
	var scene_path: String = resolve_train_scene(manifest, rules_path)
	if scene_path.is_empty():
		return manifest

	if not FileAccess.file_exists(scene_path):
		var root := Node2D.new()
		root.name = TRAIN_ROOT_NAME
		var layer := TileMapLayer.new()
		layer.name = TRAIN_LAYER_NAME
		layer.tile_set = tile_set
		root.add_child(layer)
		layer.owner = root

		var packed := PackedScene.new()
		var pack_err: Error = packed.pack(root)
		root.free()
		if pack_err != OK:
			push_error("GenService: failed to pack train scene")
			return manifest

		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scene_path.get_base_dir()))
		var save_err: Error = ResourceSaver.save(packed, scene_path)
		if save_err != OK:
			push_error("GenService: failed to save train scene %s" % scene_path)
			return manifest

		if not manifest.has("train_meta"):
			manifest["train_meta"] = default_train_meta(chunk_size)
	elif not manifest.has("train_meta"):
		manifest["train_meta"] = default_train_meta(chunk_size)

	return manifest


static func open_train_root(scene_path: String) -> Node2D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node2D


static func save_train_root(root: Node2D, scene_path: String) -> Error:
	var packed := PackedScene.new()
	var err: Error = packed.pack(root)
	if err != OK:
		return err
	return ResourceSaver.save(packed, scene_path)


static func alloc_train_dest(manifest: Dictionary, chunk_size: Vector2i) -> Dictionary:
	var meta: Dictionary = manifest.get("train_meta", {}).duplicate(true)
	if meta.is_empty():
		meta = default_train_meta(chunk_size)
	var padding: int = maxi(int(meta.get("padding", 1)), 0)
	var next_x: int = int(meta.get("next_x", 0))
	var next_y: int = int(meta.get("next_y", 0))
	var w: int = chunk_size.x
	var h: int = chunk_size.y
	var dest := Rect2i(next_x, next_y, w, h)

	meta["width"] = maxi(int(meta.get("width", w)), dest.position.x + w)
	meta["height"] = maxi(int(meta.get("height", h)), dest.position.y + h)
	meta["next_x"] = dest.position.x + w + padding
	meta["next_y"] = next_y

	var chunks: Array = meta.get("chunks", [])
	if chunks is not Array:
		chunks = []
	chunks.append({
		"x": dest.position.x,
		"y": dest.position.y,
		"w": w,
		"h": h,
	})
	meta["chunks"] = chunks
	manifest["train_meta"] = meta
	return {"manifest": manifest, "dest": dest}


static func copy_region_to_layer(
	src: TileMapLayer,
	dst: TileMapLayer,
	src_rect: Rect2i,
	dst_origin: Vector2i,
	manifest: Dictionary,
) -> void:
	var source_id: int = manifest.get("source_id", 0)
	for y in src_rect.size.y:
		for x in src_rect.size.x:
			var src_cell := src_rect.position + Vector2i(x, y)
			var dst_cell := dst_origin + Vector2i(x, y)
			var atlas := src.get_cell_atlas_coords(src_cell)
			if atlas.x < 0:
				dst.erase_cell(dst_cell)
			else:
				dst.set_cell(dst_cell, source_id, atlas)


static func load_train_map_data(manifest: Dictionary) -> Dictionary:
	var scene_path: String = resolve_train_scene(manifest)
	if scene_path.is_empty() or not FileAccess.file_exists(scene_path):
		return {}
	var meta: Dictionary = manifest.get("train_meta", {})
	var w: int = int(meta.get("width", 0))
	var h: int = int(meta.get("height", 0))
	if w <= 0 or h <= 0:
		return {}

	var root := open_train_root(scene_path)
	if root == null:
		return {}
	var layer := root.get_node_or_null(TRAIN_LAYER_NAME) as TileMapLayer
	if layer == null:
		root.free()
		return {}

	var gids: PackedInt32Array = gids_from_layer(layer, manifest, w, h, Vector2i.ZERO)
	root.free()
	return {"width": w, "height": h, "gids": gids, "path": scene_path}


static func analyze_manifest(manifest: Dictionary, chunk_size: int = 8) -> Dictionary:
	var map_data: Array = []
	var map_sources: Array = []
	for map_path in manifest.get("maps", []):
		var map: Dictionary = GenTmx.read_map(str(map_path))
		if not map.is_empty():
			map_data.append(map)
			map_sources.append(map_path)
	var train_map: Dictionary = load_train_map_data(manifest)
	if not train_map.is_empty():
		map_data.append(train_map)
		map_sources.append(train_map.get("path", resolve_train_scene(manifest)))
	var analyze: Dictionary = manifest.get("analyze", {})
	var min_adj: int = maxi(int(analyze.get("min_adj_count", 1)), 1)
	return GenRules.analyze_map_data(map_data, min_adj, manifest, chunk_size, map_sources)


static func save_rules(manifest: Dictionary, rules: Dictionary) -> Error:
	var path: String = manifest.get("rules", "")
	if path.is_empty():
		return ERR_FILE_NOT_FOUND
	return GenRules.save(path, rules)
