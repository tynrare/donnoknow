# agent: composer-2.5 | 2026-07-07 | cap adj gap-fill anti-repeat | f1a2b3
extends RefCounted

const GenTmx := preload("res://scripts/generator/tmx.gd")
const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")

const DIRS := GenTmx.DIRS
const DEFAULT_EDGE_GAP_MAX := 4
const DEFAULT_MAX_ADJ_MATES := 16
const TILED_GID_MASK := 0x1FFFFFFF
const OPPOSITE := {
	"north": "south",
	"east": "west",
	"south": "north",
	"west": "east",
}


static func analyze_maps(
	maps: Array,
	min_adj_count: int = 1,
	manifest: Dictionary = {},
) -> Dictionary:
	var tile_counts: Dictionary = {}
	var map_adjacency: Dictionary = {}
	var total := 0
	var analyze: Dictionary = manifest.get("analyze", {})
	var use_maps: bool = analyze.get("maps", true)
	var use_tileset_edges: bool = analyze.get("tileset_edges", false)
	var edge_weight_raw: float = float(analyze.get("tileset_edges_weight", 0.35))
	var edge_weight: int = maxi(int(round(edge_weight_raw * 10.0)), 1) if edge_weight_raw > 0.0 else 0
	var min_adj: int = maxi(int(analyze.get("min_adj_count", min_adj_count)), 1)
	var max_adj_mates: int = maxi(int(analyze.get("max_adj_mates", DEFAULT_MAX_ADJ_MATES)), 1)
	var tile_classes: Array = []
	var topology: Dictionary = {}
	var sources := {
		"maps": use_maps,
		"tileset_edges": use_tileset_edges,
		"min_adj_count": min_adj,
		"max_adj_mates": max_adj_mates,
		"color_quantize": int(analyze.get("color_quantize", 24)),
		"edge_quantize": int(analyze.get("edge_quantize", 32)),
		"edge_match": str(analyze.get("edge_match", "exact")),
		"alias_threshold": float(analyze.get("alias_threshold", 0.85)),
	}

	var atlas_result: Dictionary = GenAtlasAnalyze.analyze_atlas(manifest)
	tile_classes = atlas_result.get("tile_classes", [])
	topology = atlas_result.get("topology", {})

	if use_maps:
		for map_path in maps:
			var map := GenTmx.read_map(map_path)
			if map.is_empty():
				continue
			_scan_map(map, tile_counts, map_adjacency, manifest)
			total += map.width * map.height

	var adjacency: Dictionary = {}
	var active: Dictionary = _active_gid_set(tile_counts, tile_classes)
	if use_tileset_edges and edge_weight > 0:
		var edge_adj: Dictionary = _restrict_adjacency(
			atlas_result.get("adjacency", {}), active
		)
		adjacency = {}
		_merge_adjacency(adjacency, edge_adj, edge_weight)
		if use_maps:
			_merge_adjacency(adjacency, map_adjacency, 1)
	else:
		adjacency = map_adjacency

	_filter_adjacency(adjacency, min_adj)
	_symmetrize_adjacency(adjacency)
	_cap_adjacency(adjacency, max_adj_mates)
	_symmetrize_adjacency(adjacency)

	if use_tileset_edges and edge_weight > 0:
		var edge_gap_max: int = maxi(
			int(analyze.get("edge_gap_max_neighbors", DEFAULT_EDGE_GAP_MAX)), 1
		)
		var edge_adj_gap: Dictionary = _restrict_adjacency(
			atlas_result.get("adjacency", {}), active
		)
		_merge_edge_gap_fill(adjacency, edge_adj_gap, edge_weight, active, edge_gap_max)
		_symmetrize_adjacency(adjacency)
		_cap_adjacency(adjacency, max_adj_mates)
		_symmetrize_adjacency(adjacency)

	if analyze.get("trim_self_adj", true):
		var bg_gid: int = int(manifest.get("background_gid", 1))
		_trim_self_adjacency(adjacency, bg_gid)

	var tile_weights := {}
	var pick_weights := {}
	var log_total := 0.0
	for gid in tile_counts:
		log_total += log(float(tile_counts[gid]) + 1.0)
	var tile_total := 0
	for gid in tile_counts:
		tile_total += tile_counts[gid]
	for gid in tile_counts:
		tile_weights[str(gid)] = float(tile_counts[gid]) / float(maxi(tile_total, 1))
		pick_weights[str(gid)] = log(float(tile_counts[gid]) + 1.0) / maxf(log_total, 0.001)

	return {
		"version": 4,
		"tile_weights": tile_weights,
		"pick_weights": pick_weights,
		"pick_weight_mode": "log",
		"adjacency": adjacency,
		"tile_classes": tile_classes,
		"maps": maps,
		"sources": sources,
		"grid": {
			"columns": int(manifest.get("columns", 0)),
			"rows": int(manifest.get("rows", 0)),
			"first_gid": int(manifest.get("first_gid", 1)),
			"tile_count": int(manifest.get("tile_count", 0)),
			"map_width": int(manifest.get("map_width", 0)),
			"map_height": int(manifest.get("map_height", 0)),
		},
		"stats": {
			"cells": total,
			"unique_tiles": tile_counts.size(),
			"tile_classes": tile_classes.size(),
			"alias_max_class_size": int(analyze.get("alias_max_class_size", 4)),
			"max_adj_mates": max_adj_mates,
		},
	}


static func save(path: String, rules: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(rules))
	return OK


static func load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func all_tiles(rules: Dictionary, manifest: Dictionary = {}) -> PackedInt32Array:
	return generatable_tiles(rules, manifest)


static func generatable_tiles(rules: Dictionary, manifest: Dictionary = {}) -> PackedInt32Array:
	var seen: Dictionary = {}
	var bg: int = int(manifest.get("background_gid", 1))
	if bg > 0 and (manifest.is_empty() or _is_valid_gid(manifest, bg)):
		seen[bg] = true
	for k in rules.get("tile_weights", {}):
		var gid := int(k)
		if manifest.is_empty() or _is_valid_gid(manifest, gid):
			seen[gid] = true
	var packed := PackedInt32Array()
	for gid in seen:
		packed.append(gid)
	packed.sort()
	return packed


static func adj_options(rules: Dictionary, gid: int, dir: String) -> Dictionary:
	var node: Variant = rules.get("adjacency", {}).get(str(gid), {})
	if node is Dictionary:
		return node.get(dir, {})
	return {}


static func class_mates(rules: Dictionary, gid: int) -> Array:
	var cap: int = GenAtlasAnalyze.max_alias_class_size(rules)
	for class_v in rules.get("tile_classes", []):
		if class_v is not Array or class_v.size() > cap:
			continue
		for member in class_v:
			if int(member) == gid:
				return class_v
	return [gid]


static func tile_weight(rules: Dictionary, gid: int) -> float:
	return float(rules.get("tile_weights", {}).get(str(gid), 0.001))


static func pick_weight(rules: Dictionary, gid: int) -> float:
	var base := float(rules.get("pick_weights", {}).get(str(gid), 0.0))
	if base <= 0.0:
		base = tile_weight(rules, gid)
	return maxf(base, 0.0001)


static func _merge_edge_gap_fill(
	into: Dictionary,
	from: Dictionary,
	weight: int,
	active: Dictionary,
	max_neighbors: int = DEFAULT_EDGE_GAP_MAX,
) -> void:
	for gid_key in from:
		var gid: int = int(gid_key)
		if not active.has(gid):
			continue
		_ensure_adj(into, gid)
		for d in DIRS:
			var map_bucket: Dictionary = into[str(gid)][d]
			if not map_bucket.is_empty():
				continue
			var edge_bucket: Variant = from[gid_key].get(d, {})
			if edge_bucket is not Dictionary or edge_bucket.is_empty():
				continue
			var ranked: Array = []
			for nb_key in edge_bucket:
				var nb: int = int(nb_key)
				if not active.has(nb):
					continue
				ranked.append({"key": nb_key, "count": int(edge_bucket[nb_key])})
			ranked.sort_custom(func(a, b): return a.count > b.count)
			var limit: int = mini(maxi(max_neighbors, 1), ranked.size())
			for i in limit:
				var entry: Dictionary = ranked[i]
				var nb_key: String = str(entry.key)
				into[str(gid)][d][nb_key] = (
					into[str(gid)][d].get(nb_key, 0) + int(entry.count) * weight
				)


static func _trim_self_adjacency(adjacency: Dictionary, except_gid: int = 0) -> void:
	for gid_key in adjacency:
		var gid: int = int(gid_key)
		if gid == except_gid:
			continue
		for d in DIRS:
			var bucket: Dictionary = adjacency[gid_key][d]
			if bucket.has(gid_key):
				bucket.erase(gid_key)


static func _merge_adjacency(into: Dictionary, from: Dictionary, weight: int = 1) -> void:
	for gid_key in from:
		var gid: int = int(gid_key)
		_ensure_adj(into, gid)
		var src: Variant = from[gid_key]
		if src is not Dictionary:
			continue
		for d in DIRS:
			var bucket: Variant = src.get(d, {})
			if bucket is not Dictionary:
				continue
			for nb_key in bucket:
				into[str(gid)][d][nb_key] = into[str(gid)][d].get(nb_key, 0) + int(bucket[nb_key]) * weight


static func _active_gid_set(tile_counts: Dictionary, tile_classes: Array) -> Dictionary:
	var active: Dictionary = {}
	for gid in tile_counts:
		active[gid] = true
	for class_v in tile_classes:
		if class_v is not Array or class_v.size() > 12:
			continue
		for member in class_v:
			active[int(member)] = true
	return active


static func _restrict_adjacency(src: Dictionary, active: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for gid_key in src:
		var gid: int = int(gid_key)
		if not active.has(gid):
			continue
		_ensure_adj(out, gid)
		for d in DIRS:
			var bucket: Variant = src[gid_key].get(d, {})
			if bucket is not Dictionary:
				continue
			for nb_key in bucket:
				var nb: int = int(nb_key)
				if not active.has(nb):
					continue
				out[str(gid)][d][nb_key] = int(bucket[nb_key])
	return out


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
	var gid := _normalize_gid(raw)
	if not manifest.is_empty() and not _is_valid_gid(manifest, gid):
		return 0
	return gid


static func _normalize_gid(raw: int) -> int:
	return raw & TILED_GID_MASK


static func _tile_count(manifest: Dictionary) -> int:
	if manifest.has("tile_count"):
		return int(manifest.tile_count)
	var cols: int = int(manifest.get("columns", 0))
	var row_count: int = int(manifest.get("rows", 0))
	if cols > 0 and row_count > 0:
		return cols * row_count
	return 0


static func _is_valid_gid(manifest: Dictionary, gid: int) -> bool:
	var local := _normalize_gid(gid) - int(manifest.get("first_gid", 1))
	return local >= 0 and local < _tile_count(manifest)


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


static func _cap_adjacency(adjacency: Dictionary, max_mates: int) -> void:
	if max_mates <= 0:
		return
	for gid_key in adjacency:
		for d in DIRS:
			var bucket: Dictionary = adjacency[gid_key][d]
			if bucket.size() <= max_mates:
				continue
			var ranked: Array = []
			for nb_key in bucket:
				ranked.append({"key": nb_key, "count": int(bucket[nb_key])})
			ranked.sort_custom(func(a, b): return a.count > b.count)
			var kept: Dictionary = {}
			for i in mini(max_mates, ranked.size()):
				var entry: Dictionary = ranked[i]
				kept[str(entry.key)] = int(entry.count)
			adjacency[gid_key][d] = kept


static func _symmetrize_adjacency(adjacency: Dictionary) -> void:
	var pairs: Array = []
	for gid_key in adjacency:
		for d in DIRS:
			var bucket: Dictionary = adjacency[gid_key][d]
			for other in bucket:
				pairs.append([other, OPPOSITE[d], gid_key, bucket[other]])

	for pair in pairs:
		var other_key: String = pair[0]
		var opp_dir: String = pair[1]
		var back_key: String = pair[2]
		var count: int = pair[3]
		_ensure_adj(adjacency, int(other_key))
		var back_bucket: Dictionary = adjacency[other_key][opp_dir]
		back_bucket[back_key] = maxi(int(back_bucket.get(back_key, 0)), count)
