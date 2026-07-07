extends RefCounted

const GenTmx := preload("res://scripts/generator/tmx.gd")
const GenService := preload("res://scripts/generator/service.gd")

const DIRS := GenTmx.DIRS


static func analyze_maps(maps: Array, min_adj_count: int = 1, manifest: Dictionary = {}) -> Dictionary:
	var tile_counts: Dictionary = {}
	var adjacency: Dictionary = {}
	var total := 0

	for map_path in maps:
		var map := GenTmx.read_map(map_path)
		if map.is_empty():
			continue
		_scan_map(map, tile_counts, adjacency, manifest)
		total += map.width * map.height

	var tile_weights := {}
	var tile_total := 0
	for gid in tile_counts:
		tile_total += tile_counts[gid]
	for gid in tile_counts:
		tile_weights[str(gid)] = float(tile_counts[gid]) / float(maxi(tile_total, 1))

	_filter_adjacency(adjacency, min_adj_count)

	return {
		"version": 1,
		"tile_weights": tile_weights,
		"adjacency": adjacency,
		"maps": maps,
		"stats": {
			"cells": total,
			"unique_tiles": tile_counts.size(),
		},
	}


static func save(path: String, rules: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(rules, "\t"))
	return OK


static func load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func all_tiles(rules: Dictionary, manifest: Dictionary = {}) -> PackedInt32Array:
	var out: Array = []
	for k in rules.get("tile_weights", {}):
		var gid := int(k)
		if manifest.is_empty() or GenService.is_valid_gid(manifest, gid):
			out.append(gid)
	out.sort()
	var packed := PackedInt32Array()
	for gid in out:
		packed.append(gid)
	return packed


static func adj_options(rules: Dictionary, gid: int, dir: String) -> Dictionary:
	var node: Variant = rules.get("adjacency", {}).get(str(gid), {})
	if node is Dictionary:
		return node.get(dir, {})
	return {}


static func tile_weight(rules: Dictionary, gid: int) -> float:
	return float(rules.get("tile_weights", {}).get(str(gid), 0.001))


static func _scan_map(map: Dictionary, tile_counts: Dictionary, adjacency: Dictionary, manifest: Dictionary) -> void:
	var w: int = map.width
	var h: int = map.height
	var gids: PackedInt32Array = map.gids

	for y in h:
		for x in w:
			var a := _cell_gid(gids[y * w + x], manifest)
			if a <= 0:
				continue
			tile_counts[a] = tile_counts.get(a, 0) + 1
			_ensure_adj(adjacency, a)

			if y > 0:
				var b := _cell_gid(gids[(y - 1) * w + x], manifest)
				if b > 0:
					adjacency[str(a)]["north"][str(b)] = adjacency[str(a)]["north"].get(str(b), 0) + 1
			if x < w - 1:
				var b_e := _cell_gid(gids[y * w + x + 1], manifest)
				if b_e > 0:
					adjacency[str(a)]["east"][str(b_e)] = adjacency[str(a)]["east"].get(str(b_e), 0) + 1
			if y < h - 1:
				var b_s := _cell_gid(gids[(y + 1) * w + x], manifest)
				if b_s > 0:
					adjacency[str(a)]["south"][str(b_s)] = adjacency[str(a)]["south"].get(str(b_s), 0) + 1
			if x > 0:
				var b_w := _cell_gid(gids[y * w + x - 1], manifest)
				if b_w > 0:
					adjacency[str(a)]["west"][str(b_w)] = adjacency[str(a)]["west"].get(str(b_w), 0) + 1


static func _cell_gid(raw: int, manifest: Dictionary) -> int:
	if raw <= 0:
		return 0
	var gid := GenService.normalize_gid(raw)
	if not manifest.is_empty() and not GenService.is_valid_gid(manifest, gid):
		return 0
	return gid


static func _ensure_adj(adjacency: Dictionary, gid: int) -> void:
	var key := str(gid)
	if adjacency.has(key):
		return
	adjacency[key] = {}
	for d in DIRS:
		adjacency[key][d] = {}


static func _filter_adjacency(adjacency: Dictionary, min_count: int) -> void:
	for gid_key in adjacency:
		for d in DIRS:
			var bucket: Dictionary = adjacency[gid_key][d]
			for other in bucket.keys():
				if bucket[other] < min_count:
					bucket.erase(other)
